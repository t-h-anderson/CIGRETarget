classdef ModelDescription < handle
    %MODELDESCRIPTION

    properties
        CIGRESuffix (1,1) string = "" % Cigre wrapper - reduce chance of clash with globals. Only "" works at the moment
        MaxExternalIdentifier (1,1) double = 31
    end

    properties
        CodeGenFolder
        WorkFolder
    end

    % Model metadata properties
    properties
        ModelName (1,1) string      % Top level model to be built
        InterfaceName (1,1) string  % Interface definition, can be a wrapper for the model
        WrapperName (1,1) string        % Top level wrapper to allow model reference code to be built

        DLLName (1,1) string
        ModelVersion (1,1) string = "Unknown"
        Description (1,1) string = ""

        SampleTime (1,1) string = ""

        CreatedBy (1,1) string = ""
        CreatedOn (1,1) string = ""

        ModifiedBy (1,1) string = "Unknown"
        ModifiedOn (1,1) string = ""

        ModelModifiedComment (1,1) string = ""
        ModelModifiedHistory (1,1) string = ""

        SystemTargetFile (1,1) string = "cigre"

        RTMStructName = "RealTimeModel_T" % Real-time Model Data Structure
        RTMVarType (1,1) string
        RTMStruct (1,:) cigre.description.Variable % Variable and name in RTM Struct
    end

    properties (Constant)
        ReservedNames (1,:) string = ["inputs", "outputs"];
    end

    % Build info properties
    properties
        BuildDir (1,1) string = ""
    end

    % Code info properties
    properties
        Inputs cigre.description.Variable
        Outputs cigre.description.Variable
        Parameters cigre.description.Variable

        InputData (1,:) cigre.description.Variable
        OutputData (1,:) cigre.description.Variable
        InternalData (1,:) cigre.description.Variable

        % Function interfaces
        ModelRefInitialiseName (1,1) string = ""
        ModelRefInitialiseInputs (1,:) cigre.description.Variable

        InitializeName (1,1) string = ""
        InitialiseInputs (1,:) cigre.description.Variable

        StepName (1,1) string = ""
        StepInputs (1,:) cigre.description.Variable

        TerminateName (1,1) string = ""
        TerminateInputs (1,:) cigre.description.Variable

        % Rate scheduler
        RateSchedulerCode (1,1) string = ""

        % Timing bridge
        TimingBridgeCode (1,1) string = ""
        NumberOfTasks (1,1) double = 1

        % Initialize Only Code
        InitializeOnlyCode (1,1) string = ""

    end

    properties (Dependent)
        WrapperCodeDescriptor
        InterfaceCodeDescriptor
        ModelCodeDescriptor

        InterfaceCodeInfo
        WrapperCodeInfo

        HasTimingBridge
        HasInitFunction
        HasRateScheduler
    end

    properties (Access = protected)
        WrapperCodeDescriptor_
        InterfaceCodeDescriptor_
        ModelCodeDescriptor_
        
        InterfaceCodeInfo_
        WrapperCodeInfo_
    end

    methods
        function obj = ModelDescription(modelName, nvp)
            arguments
                modelName (1,1) string
                nvp.InterfaceName (1,1) string = modelName % Can be different from the model
                nvp.WrapperName (1,1) string = string(missing)
            end

            obj.ModelName = modelName;
            obj.InterfaceName = nvp.InterfaceName;
            obj.WrapperName = nvp.WrapperName;

            cfg = Simulink.fileGenControl('getConfig');
            obj.CodeGenFolder = cfg.CodeGenFolder;
            obj.WorkFolder = cfg.CacheFolder;
        end

        function clearCodeDescriptorObjects(obj)
            % Do this after analysis otherwise the file will be locked
            delete(obj.InterfaceCodeDescriptor_);
            delete(obj.ModelCodeDescriptor_);
            delete(obj.WrapperCodeDescriptor_);

            delete(obj.InterfaceCodeInfo_);
            delete(obj.WrapperCodeInfo_);

        end

        function analyse(obj)

            % Load the system so we can get_param
            cModel = util.loadSystem(obj.ModelName); %#ok<NASGU>
            cInterface = util.loadSystem(obj.InterfaceName); %#ok<NASGU>
            cWrapper = util.loadSystem(obj.WrapperName); %#ok<NASGU>

            cCodeDescriptor = onCleanup(@() obj.clearCodeDescriptorObjects());

            % Get metadata from the model - no interraction with build
            % objects
            obj.getModelMetadata();

            % Get information from the wrapper code - this is created for a
            % top level model, but not for a reference model. This is used
            % in the cigre dll code
            obj.loadTimingBridgeCode();
            obj.loadInitializeOnlyCode();
            obj.loadRateSchedulerCode();

            obj.loadInternalData();

            % Get information about the data interfaces, i.e. the input,
            % output and parameters
            obj.loadDataInterface("Input");
            obj.loadDataInterface("Output");
            obj.loadDataInterface("Parameters");

            % Get call signatures for the four key functions

            % Model reference - allow snapshot restart
            obj.getFunctionInterface("Init"); 
            
            % Top model
            obj.getFunctionInterface("Initialise");
            obj.getFunctionInterface("Step");
            obj.getFunctionInterface("Terminate");

            obj.clearCodeDescriptorObjects();
        end

        function writeDLLSource(obj, writer)
            arguments
                obj (1,1)
                writer (1,1) cigre.writer.CIGREWriter
            end

            [dllText, cFile] = writer.writeDLL(obj);
            [headerText, hFile] = writer.writeHeader(obj);

            here = Simulink.fileGenControl('getConfig').CodeGenFolder; % TODO: This isn't good for testing. Inject location?
            buildDir = fullfile(here, "slprj", "cigre");

            writeToFile(dllText, fullfile(buildDir, cFile));
            writeToFile(headerText, fullfile(buildDir, hFile));

        end

    end

    methods (Access = protected)

        function getModelMetadata(obj)

            model = obj.ModelName;
            cModel = util.loadSystem(model); %#ok<NASGU>

            obj.SystemTargetFile = erase(get_param(model, "SystemTargetFile"), ".tlc");

            obj.ModifiedBy = get_param(model, "LastModifiedBy");
            obj.ModifiedOn = get_param(model, "LastModifiedDate");
            obj.CreatedBy = get_param(model, "Creator");
            obj.CreatedOn = get_param(model, "Created");
            obj.CreatedOn = get_param(model, "Description");
            obj.ModelModifiedComment = get_param(model, "ModifiedComment");
            obj.ModelModifiedHistory = get_param(model, "ModifiedHistory");
            obj.ModelVersion = get_param(model, "ModelVersion");

            try
                step = get_param(model, "CompiledStepSize");
                if string(step) == "auto"
                    error("Step size 'auto' not supported");
                end

                obj.SampleTime = evalin('base', step); % TODO: How do we eval this like the model?
            catch
                error("ModelDescription:StepSizeNotCalculated", "Step size " + step + " could not be evaluated");
            end

        end

        function loadTimingBridgeCode(obj)
            % Find the number of tasks and

            % Example timing bridge code:
            % typedef struct tag_RTM_Test_MultiInputTopLevel_T {
            % 	rtTimingBridge timingBridge;
            %   struct {
            %     struct {
            %       uint32_T TID[2];
            %     } TaskCounters;
            %   } Timing;
            % } RT_MODEL_Test_MultiInputTopLevel_T;"], newline)
            headerCode = obj.getWrapperCode("Type", ".h");
            [tbc, nTasks] = obj.processRTMStructCode(headerCode);

            obj.TimingBridgeCode = tbc;
            obj.NumberOfTasks = nTasks;

        end

        function loadInitializeOnlyCode(obj)
            % Find the number of tasks and

            % Example timing bridge code:
            % void Snap_iwrap_wrap_initialize_only(RT_MODEL_Snap_iwrap_wrap_T* const
            % Snap_iwrap_wrap_M)
            % {
            %     DW_Snap_iwrap_wrap_T* Snap_iwrap_wrap_DW = Snap_iwrap_wrap_M->dwork;
            % 
            %     {
            %     static uint32_T* taskCounterPtrs;
            %     Snap_iwrap_wrap_M->timingBridge.nTasks = 3;
            %     Snap_iwrap_wrap_M->timingBridge.clockTick = (NULL);
            %     Snap_iwrap_wrap_M->timingBridge.clockTickH = (NULL);
            %     taskCounterPtrs = &(Snap_iwrap_wrap_M->Timing.TaskCounters.TID[0]);
            %     Snap_iwrap_wrap_M->timingBridge.taskCounter = taskCounterPtrs;
            %     }
            % 
            %     /* Model Initialize function for ModelReference Block: '<Root>/mdl' */
            %         Snap_iwrap_initialize(rtmGetErrorStatusPointer(Snap_iwrap_wrap_M),
            %         &Snap_iwrap_wrap_M->timingBridge, 0, 1, 2,
            %         &(Snap_iwrap_wrap_DW->mdl_InstanceData.rtm),
            %         &(Snap_iwrap_wrap_DW->mdl_InstanceData.rtdw));
            % 
            % }

            wrapperCode = obj.getWrapperCode("Type", ".c");
            initialize = obj.processInitializeCode(wrapperCode);

            obj.InitializeOnlyCode = initialize;

        end

        function loadRateSchedulerCode(obj)
            % TODO: Make more stable. Can include other code which may have
            % include dependencies
            headerCode = obj.getWrapperCode("Type", ".c");
            code = obj.processRateSchedulerCode(headerCode, obj.WrapperName);

            obj.RateSchedulerCode = code;
        end

        function loadInternalData(obj)
            %
            % % Code Descriptor
            % codeDescObj = obj.ModelCodeDescriptor;
            % internal = codeDescObj.getDataInterfaces("InternalData");
            %
            % type = arrayfun(@(x) string(x.Implementation.BaseRegion.Type.Identifier), internal);
            % [~, idx] = unique(type, "stable");
            % type = num2cell(type(idx));
            %
            % try
            %     name = arrayfun(@(x) string(x.Implementation.BaseRegion.ElementIdentifier), internal, "UniformOutput", false);
            %     name = name(idx);
            % catch
            %     % This fails in 2020a
            %     name = "internalState" + (1:numel(type));
            % end

            % Code info
            codeInfo = obj.WrapperCodeInfo;

            id = codeInfo.InternalData;

            % Dealt with cetain fields of model struct explicitly
            name = obj.extractName(id);
            idx = cellfun(@(x) x == "rt_errorStatus", name);
            idx = idx | cellfun(@(x) x == "timingBridge", name);
            idx = idx | cellfun(@(x) contains(x, "mdlref_TID"), name);
            id(idx) = [];
            
            % Ensure we don't have any name clases
            name = obj.extractName(id);
            name = obj.avoidReservedName(name);

            [type, pointers] = obj.extractType(id);

            % Separate external input and outputs
            idxInput = (string({id.GraphicalName}) == "ExternalInput");
            idxOutput = (string({id.GraphicalName}) == "ExternalOutput");
            idxInternal = (~idxInput & ~idxOutput);

            % Always at least one pointer used in writer. Why do we have a
            % difference?
            idx = cellfun(@(x) x == "", pointers);
            pointers(idx) = {"*"};

            obj.InputData = cigre.description.Variable.create("Name", name(idxInput), "Type", type(idxInput), "Pointers", pointers(idxInput));
            obj.OutputData = cigre.description.Variable.create("Name", name(idxOutput), "Type", type(idxOutput), "Pointers", pointers(idxOutput));
            obj.InternalData = cigre.description.Variable.create("Name", name(idxInternal), "Type", type(idxInternal), "Pointers", pointers(idxInternal));

            obj.getRTMStruct();
        end

        function getRTMStruct(obj)

            % Ignore Inputs, outputs and RTM
            idx = find(endsWith([obj.InternalData.Name], "_M" + textBoundaryPattern), 1); % TODO: Make this more robust
            if isempty(idx)
                idx = find(contains([obj.InternalData.Name], "MODEL"), 1); % TODO: Make this more robust
            end

            obj.RTMVarType = obj.InternalData(idx).Type;
            obj.RTMStruct = obj.InternalData((idx+1):end);

            % Remove from the heap. It is stored independently
            obj.InternalData(idx) = [];

        end

        function getFunctionInterface(obj, type)
            arguments
                obj
                type (1,1) string {mustBeMember(type, ["Init", "Initialise", "Step", "Terminate", "Start"])}
            end

            switch type
                case "Init"
                    obj.loadModelRefInitialiseFunctionInterface();
                case "Start"
                    obj.loadStartFunctionInterface();
                case "Initialise"
                    obj.loadInitialiseFunctionInterface();
                case "Step"
                    obj.loadStepFunctionInterface();
                case "Terminate"
                    obj.loadTerminateFunctionInterface();
            end

        end

        function loadModelRefInitialiseFunctionInterface(obj)

            [name, inputs] = getCodeInterfaceForModelRef(obj, "Type", "Initialize");

            obj.ModelRefInitialiseName = name;
            obj.ModelRefInitialiseInputs = inputs;

        end

        function loadInitialiseFunctionInterface(obj)

            codeDescObj = obj.WrapperCodeDescriptor;
            initialise = codeDescObj.getFunctionInterfaces("Initialize");

            args = initialise.ActualArgs;
            intInputs = string(obj.extractName(args));
            types = string(obj.extractType(args));

            intInputs = obj.translateNames(intInputs, types);
            inputs = cigre.description.Variable.create("Name", intInputs, "Type",types);

            obj.InitialiseInputs = inputs;

            obj.InitializeName = initialise.Prototype.Name;

        end

        function loadStepFunctionInterface(obj)

            codeDescObj = obj.WrapperCodeDescriptor;
            step = codeDescObj.getFunctionInterfaces("Output");

            args = step.ActualArgs;
            stepInputs = string(obj.extractName(args.toArray()));
            types = string(obj.extractType(args.toArray()));

            stepInputs = obj.translateNames(stepInputs, types);
            inputs = cigre.description.Variable.create("Name", stepInputs, "Type",types);

            obj.StepInputs = inputs;

            obj.StepName = step.Prototype.Name;
        end

        function loadTerminateFunctionInterface(obj)
            codeDescObj = obj.ModelCodeDescriptor;

            % Terminate function interface
            terminate = codeDescObj.getFunctionInterfaces("Terminate");

            try
                obj.TerminateName = terminate.Prototype.Name;
            catch
                % Fails as no terminate function
                obj.TerminateName = "";
            end

        end

        function code = getWrapperCode(obj, nvp)
            arguments
                obj
                nvp.Type (1,1) string {mustBeMember(nvp.Type, [".h", ".c"])} = ".h"
            end

            % Load the wrapper header file by naming convention
            here = obj.CodeGenFolder;
            wrapper = obj.WrapperName;
            wrapperHeader = fullfile(here, wrapper + "_cigre_rtw", wrapper + nvp.Type);

            if ~isfile(wrapperHeader)
                error("CIGRE:TimingBridgeCode:NoWrapperCode", "No file found for the CIGRE wrapper model at " + wrapperHeader);
            end

            code = readFromFile(wrapperHeader);
        end

        function [funcName, inputs] = getCodeInterfaceForModelRef(md, nvp)
            arguments
                md
                nvp.Type {mustBeMember(nvp.Type, ["Init", "Start", "Initialize"])}
            end

            type = nvp.Type;

            model = md.InterfaceName;
            codeDescObj = md.InterfaceCodeDescriptor;

            if verLessThan("MATLAB", "9.14")

                sourceFile = model + ".c";

                f = readFromFile(fullfile(codeDescObj.BuildDir, sourceFile));

                % Get the block with the tag_RTM
                idxStart = find(contains(f, "void " + model + "_" + type + "("), 1);

                inputTypes = string.empty(1,0);
                inputNames = string.empty(1,0);
                pointers = string.empty(1,0);
                funcName = "";

                if ~isempty(idxStart)

                    % Function can span mulitple lines
                    initFn = f(idxStart:end);
                    idxEnd = find(contains(initFn, ")"), 1);
                    initFn = strjoin(initFn(1:idxEnd), "");

                    % Take arguments
                    funcName = extractBetween(initFn, " ", "(");
                    argsIn = extractBetween(initFn, "(", ")");

                    argsIn = strtrim(strsplit(argsIn, ","));
                    for i = 1:numel(argsIn)
                        thisArg = strsplit(argsIn(i), " ");
                        inputTypes(i) = thisArg(1);
                        pointers(i) = ""; % TODO
                        inputNames(i) = erase(thisArg(2), "*");
                    end

                end

            else
                init = codeDescObj.getServiceFunctionPrototype(model + "_" + type); %  TODO: Show How do we find this?

                if ~isempty(init)
                    funcName = init.Name;
                    args = init.Arguments;
                    args = args.toArray();

                    inputNames = string({args.Name});
                    [inputTypes, pointers] = md.extractType(struct("Implementation", args));
                else
                    funcName = "";
                    inputNames = string.empty(1,0);
                    inputTypes = string.empty(1,0);
                    pointers = string.empty(1,0);
                end

            end

            inputNames = md.translateNames(inputNames, inputTypes);

            inputs = cigre.description.Variable.create("Name", inputNames, "Pointers", pointers, "Type", inputTypes);

        end

        %coder.descriptor.types.Argument

        function loadDataInterface(obj, type)
            arguments
                obj
                type (1,1) string {mustBeMember(type, ["Input", "Output", "Parameters"])}
            end

            switch type
                case "Input"
                    obj.loadInputInterface();
                case "Output"
                    obj.loadOutputInterface();
                case "Parameters"
                    obj.loadParameterInterface();
            end
        end

        function loadInputInterface(obj)
            inports = obj.InterfaceCodeDescriptor.getDataInterfaces("Inports");
            obj.Inputs = cigre.description.Variable.create(...
                "GraphicalName", obj.extractGraphicalName(inports), ...
                "Name", obj.extractName(inports), ...
                "Type", obj.extractType(inports), ...
                "BaseType", obj.extractBaseType(inports), ...
                "Dimensions", obj.extractDimensions(inports) ...
                );
        end

        function loadOutputInterface(obj)
            outports = obj.InterfaceCodeDescriptor.getDataInterfaces("Outports");
            obj.Outputs = cigre.description.Variable.create(...
                "GraphicalName", obj.extractGraphicalName(outports), ...
                "Name", obj.extractName(outports), ...
                "Type", obj.extractType(outports), ...
                "BaseType", obj.extractBaseType(outports), ...
                "Dimensions", obj.extractDimensions(outports)  ...
                );
        end

        function loadParameterInterface(obj)
            parameters = obj.ModelCodeDescriptor.getDataInterfaces("Parameters");
            obj.Parameters = cigre.description.Variable.create(...
                "GraphicalName", obj.extractGraphicalName(parameters), ...
                "Name", obj.extractName(parameters), ...
                "Type", obj.extractType(parameters), ...
                "BaseType", obj.extractBaseType(parameters), ...
                "Min", obj.extract(parameters, "Min"), ...
                "Max", obj.extract(parameters, "Max"), ...
                "Dimensions", obj.extractDimensions(parameters),...
                "DefaultValue", obj.extractDefaultParamValue(parameters)...
                );
        end

        function inputNames = translateNames(obj, inputNames, inputTypes)
            arguments
                obj
                inputNames (1,:) string
                inputTypes (1,:) string
            end
            % Convert from types to names using internal data - ideally
            % this could be quite fragile, this should be replaced

            knownTypes = string([obj.InternalData.Type obj.InputData.Type obj.OutputData.Type]);
            knownNames = string([obj.InternalData.Name obj.InputData.Name obj.OutputData.Name]);

            % Replace graphial names "rtx_"/"rty_" + graphical name with
            % the internal name
            inputNames = erase(inputNames, ["rty_", "rtx_"]);
            graphicalNames = [[obj.Inputs.GraphicalName], [obj.Outputs.GraphicalName]];
            names = [[obj.Inputs.Name], [obj.Outputs.Name]];
            for i = 1:numel(inputNames)
                idx = ismember(graphicalNames, inputNames(i));
                if any(idx)
                    inputNames(i) = names(idx);
                end
            end

            for i = 1:numel(inputTypes)
                if isempty(inputTypes(i))
                    continue
                end
                idx = ismember(knownTypes, inputTypes(i));

                if sum(idx) == 1
                    inputNames(i) = knownNames(idx);
                else
                    % warning(inputTypes(i) + " not a know type");
                end
            end

            % Replace RTM
            idx = inputTypes == obj.RTMVarType;
            inputNames(idx) = obj.RTMStructName;
        end

        function value = extractDefaultParamValue(obj, interface)
            value = cell(1, numel(interface));
            failedValue = 0; % Nan may be better, but also possibly not supported. 0 is safe.
            for i = 1:numel(interface)
                try
                    value{i} = util.findParam(obj.ModelName, interface(i).GraphicalName);
                catch
                    value{i} = failedValue; % Not found
                end
            end

            value = [value{:}]';
        end

    end

    methods % Dependent
        % Take care to close code descriptor files after use
        function val = get.WrapperCodeDescriptor(obj)

            if ~isempty(obj.WrapperCodeDescriptor_) && isvalid(obj.WrapperCodeDescriptor_)
                val = obj.WrapperCodeDescriptor_;
            else
                wrapper = obj.WrapperName;
                val = coder.getCodeDescriptor(wrapper);
                obj.WrapperCodeDescriptor_ = val;
            end

        end

        function val = get.InterfaceCodeDescriptor(obj)

            if ~isempty(obj.InterfaceCodeDescriptor_) && isvalid(obj.InterfaceCodeDescriptor_)
                val = obj.InterfaceCodeDescriptor_;
            else
                wrapObj = obj.WrapperCodeDescriptor;
                model = obj.InterfaceName;
                val = getReferencedModelCodeDescriptor(wrapObj, model);
                obj.InterfaceCodeDescriptor_ = val;
            end

        end

        function val = get.ModelCodeDescriptor(obj)

            if ~isempty(obj.ModelCodeDescriptor_) && isvalid(obj.ModelCodeDescriptor_)
                val = obj.ModelCodeDescriptor_;
            else
                wrapObj = obj.WrapperCodeDescriptor;
                model = obj.ModelName;
                val = getReferencedModelCodeDescriptor(wrapObj, model);
                obj.ModelCodeDescriptor_ = val;
            end

        end

        function val = get.InterfaceCodeInfo(obj)

            if ~isempty(obj.InterfaceCodeInfo_) && isvalid(obj.InterfaceCodeInfo_)
                val = obj.InterfaceCodeInfo_;
            else
                here = Simulink.fileGenControl('getConfig').CodeGenFolder;
                codeInfo =  fullfile(here, "slprj\cigre", obj.InterfaceName, obj.InterfaceName + "_mr_codeInfo.mat");
                val = load(codeInfo).codeInfo;
                obj.InterfaceCodeInfo_ = val;
            end

        end

        function val = get.WrapperCodeInfo(obj)

            if ~isempty(obj.WrapperCodeInfo_) && isvalid(obj.WrapperCodeInfo_)
                val = obj.WrapperCodeInfo_;
            else
                here = Simulink.fileGenControl('getConfig').CodeGenFolder;
                codeInfo =  fullfile(here, obj.WrapperName + "_cigre_rtw", "codeInfo.mat");
                val = load(codeInfo).codeInfo;
                obj.WrapperCodeInfo_ = val;
            end

        end

        function value = get.HasTimingBridge(obj)
            if contains(obj.TimingBridgeCode, "timingBridge")
                value = true;
            else
                value = false;
            end
        end

        function value = get.HasInitFunction(obj)
            if obj.ModelRefInitialiseName == ""
                value = false;
            else
                value = true;
            end
        end

        function value = get.HasRateScheduler(obj)
            if obj.RateSchedulerCode == ""
                value = false;
            else
                value = true;
            end
        end


        function delete(obj)
            obj.clearCodeDescriptorObjects();
        end

    end

    methods (Static)

        function desc = analyseModel(model, interface, wrapper)
            arguments
                model (1,1) string
                interface (1,1) string = model
                wrapper (1,1) string = cigre.internal.cigreWrap(model)
            end

            desc = cigre.description.ModelDescription(model, "InterfaceName", interface, "WrapperName", wrapper);
            desc.analyse();

        end

        % Local functions
        function name = extractGraphicalName(interface)

            name  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                name{i} = string(interface(i).GraphicalName);
            end

        end

        function name = extractName(interface)

            name  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                % Look at the implementation for the name
                imp = interface(i).Implementation;

                if isa(imp, "coder.descriptor.Variable") || isa(imp, "RTW.Variable")
                %if isprop(imp, "Identifier") && ~isempty(imp.Identifier)
                    name{i} = imp.Identifier;
                elseif isprop(imp, "ElementIdentifier") && ~isempty(imp.ElementIdentifier)
                    name{i} = imp.ElementIdentifier;
                elseif isprop(imp, "Type")
                    % We want the property name
                    type = imp.Type;

                    while(isa(type, "coder.types.Pointer"))
                        % Drill into pointer
                        type = type.BaseType;
                    end

                    name{i} = type.Name;
                end

            end   

        end

        function [types, pointers] = extractType(interface)

            types = cell(1, numel(interface));
            pointers = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                try
                    type = interface(i).Implementation.Type;

                    [type, pointer] = getPointerType(type);

                    types{i} = string(type.Identifier);
                    pointers{i} = pointer;

                catch
                    types{i} = "";
                    pointers{i} = "";
                end

            end

        end

        function types = extractBaseType(interface)

            types  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                try
                    types{i} = string(interface(i).Type.BaseType.Name);
                catch
                    types{i} = string(interface(i).Type.Name);
                end
            end

        end

        function value = extractDimensions(interface)
            value = cell(1, numel(interface));
            for i = 1:numel(interface)
                try
                    % TODO: why so many try catches?
                    value{i} = interface(i).Type.Dimensions.toArray();
                catch
                    try
                        value{i} = interface(i).Type.Dimensions;
                    catch
                        value{i} = [1,1];
                    end
                end
            end
        end

        function limitVal = extract(interface, lim)

            type = cigre.description.ModelDescription.extractBaseType(interface);

            limitVal  = cell(1, numel(interface));
            for i = 1:numel(interface)
                limitVal{i} = string(interface(i).Range.(lim));

                if contains(type{i}, "int", "IgnoreCase", true)
                    isInt = true;
                else
                    isInt = false;
                end

                % Assumes we never have e.g. -inf on a max
                if string(limitVal{i}) == "-inf" || string(limitVal{i}) == ""
                    if isInt
                        limitVal{i} = intmin(type{i});
                    else
                        limitVal{i} = realmin;
                    end
                end

                if string(limitVal{i}) == "inf" || string(limitVal{i}) == ""
                    if isInt
                        limitVal{i} = intmax(type{i});
                    else
                        limitVal{i} = realmax / 2; % Using realmax cases a "constant too large error"
                    end
                end
            end

            limitVal = [limitVal{:}]';
        end

        function [tbc, nTasks] = processRTMStructCode(headerCode)
            arguments
                headerCode string
            end

            if numel(headerCode) == 1
                headerCode = strsplit(headerCode, newline);
            end

            % Get the code line that starts with struct tag_
            idxStart = find(contains(headerCode, "struct tag_"), 1);

            if ~isempty(idxStart)
                % The timing bridge block ends with "};"
                idxEnd = findLineStartText(headerCode, "}");
                idxEnd = idxEnd(find(idxEnd > idxStart, 1));

                code = headerCode(idxStart:idxEnd);

                % Make the struct into a typedef so we can use it
                if ~contains(code(1), "typedef")
                    code(1) = "typedef " + code(1);
                end

                code(end) = "}<<RTMStruct>>;";

                % Find number of tasks
                tmp = strjoin(code, newline);
                nTasks = extractBetween(tmp, "TID[", "]");
                if isempty(nTasks)
                    nTasks = "0";
                end

                % See if contains timing bridge

                tbc = code(1);

                if any(contains(code, "errorStatus"))
                    tbc = [tbc; "  const char_T *errorStatus;"];
                end

                if any(contains(code, "rtTimingBridge"))
                    tbc = [tbc; "  rtTimingBridge timingBridge;"];
                end

                % Update number of tasks
                if nTasks == "0"
                    nTasks = "1";
                else
                    tbc = [tbc
                        "  /*"
                        "   * Timing:"
                        "   * The following substructure contains information regarding"
                        "   * the timing information for the model."
                        "   */"
                        "  struct {"
                        "    struct {"
                        "      uint32_T TID[" + nTasks + "];"
                        "    } TaskCounters;"
                        "  } Timing;"
                        ];
                end

                tbc = [tbc; code(end)];

                tbc = strjoin(tbc, newline);

            else
                % tag_RTM not found, so we are a single rate model without
                % a timing bridge
                tbc = "";
                nTasks = 1;
            end

        end

        function code = processRateSchedulerCode(srcCodeIn, wrapperName)
            arguments
                srcCodeIn (:, 1) string
                wrapperName (1,1) string
            end

            srcCode = srcCodeIn;
            if numel(srcCode) == 1
                srcCode = strsplit(srcCode, newline)';
            end

            % Get the block with the tag_RTM
            idxStart = find(contains(srcCode, "rate_scheduler"));
            if numel(idxStart) > 1
                % First one is definition;
                idxStart = idxStart(2);
            end

            if ~isempty(idxStart)

                idxEnd = findLineStartText(srcCode, "}");
                idxEnd = idxEnd(find(idxEnd > idxStart, 1));

                code = srcCode(idxStart:idxEnd);

                % Replace method call with standard
                idxEnd = find(contains(code, ")"), 1);
                code(1:idxEnd) = [];
                code = ["static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)"; code];

                if code(2) ~= "{"
                    code = [code(1); "{"; code(2:end)];
                end

                code = regexprep(code, wrapperName + "_M", "RealTimeModel_M");

            else
                % Ensure there is always a rate scheduler
                code = [...
                    "static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)" ...
                    "{" ...
                    "}"
                    ];
            end

            % TODO: Make more robust - this removes block io which requires
            % a different include
            idx = contains(code, "B_");
            idx2 = contains(code, "*blockIO");
            code(idx|idx2) = [];

            code = strjoin(code, newline);
        end

        function code = processInitializeCode(srcCodeIn)
            arguments
                srcCodeIn (:, 1) string
            end

            srcCode = srcCodeIn;
            if isscalar(srcCode)
                srcCode = strsplit(srcCode, newline)';
            end

            % Get the block with the tag_RTM
            idxStart = find(contains(srcCode, "/* Model initialize function"));
            if numel(idxStart) > 1
                % First one is definition;
                idxStart = idxStart(2);
            end

            if ~isempty(idxStart)
                % Find the end of the initialize function call
                % "  /* Model Initialize function for ModelReference Block: '<Root>/mdl' */"
                %   "  InterOPERA_iwrap_initialize(rtmGetErrorStatusPointer(InterOPERA_iwrap_wrap_M),"
                %   "    &InterOPERA_iwrap_wrap_M->timingBridge, 0, 1, 2, 3,"
                %   "    &(InterOPERA_iwrap_wrap_DW->mdl_InstanceData.rtm),"
                %   "    &(InterOPERA_iwrap_wrap_DW->mdl_InstanceData.rtdw));"
                % See the first ");" after the "_initialize(" call

                idxInitialize = find(contains(srcCode,  "_initialize("), 1, "last");
                idxEnd = find(contains(srcCode, ");"));
                idxEnd = idxEnd(find(idxEnd > idxInitialize, 1));

                if isempty(idxEnd)
                    % No initialize function
                    idxEnd = findLineStartText(srcCode, "}");
                end

                idxEnd = idxEnd(find(idxEnd > idxStart, 1));

                code = srcCode(idxStart:idxEnd);

                % Close out the initialize only function
                code = [code; "}"];

            else
                % Ensure there is always an initialize only function
                code = [...
                    "{" ...
                    "}"
                    ];
            end

            % Add _only to function name
            code(2) = insertAfter(code(2), "_initialize", "_only");
           
            code = strjoin(code, newline);

        end

        function names = avoidReservedName(names)
            arguments
                names (1,:) cell
            end

            for i = 1:numel(names)
                names{i} = matlab.lang.makeUniqueStrings(names{i}, cigre.description.ModelDescription.ReservedNames);
            end

        end

    end

end

function [type, pointers] = getPointerType(type)

pointers = "";
if meta.class.fromName(class(type)) <= ?coder.types.Pointer || ...
        meta.class.fromName(class(type)) <= ?coder.descriptor.types.Pointer || ...
        meta.class.fromName(class(type)) <= ?coder.descriptor.types.Matrix
    type = type.BaseType;
    [type, pointers] = getPointerType(type);
    pointers = pointers + "*";
end

end

