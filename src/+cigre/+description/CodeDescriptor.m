classdef CodeDescriptor < handle
    % Wraps the Simulink coder.CodeDescriptor API
    
    properties (Access = private)
        ModelName_ (1,1) string
        CIGREInterfaceName_ (1,1) string
        CodeGenFolder_ (1,1) string
        CIGREDescriptor_  % cached coder.CodeDescriptor for the wrapper model
        ModelDescriptor_  % cached coder.CodeDescriptor for the referenced model
        CodeInfo_         % cached codeInfo struct from codeInfo.mat
    end

     methods

        function obj = CodeDescriptor(modelName, cigreInterfaceName, codeGenFolder)
            arguments
                modelName (1,1) string
                cigreInterfaceName (1,1) string
                codeGenFolder (1,1) string
            end
            obj.ModelName_ = modelName;
            obj.CIGREInterfaceName_ = cigreInterfaceName;
            obj.CodeGenFolder_ = codeGenFolder;
        end

        function metadata = getModelMetadata(obj)
            % Read model properties via get_param and return a ModelMetadata
            % value object so callers have no dependency on the Simulink API.
            model = obj.ModelName_;
            cModel = util.loadSystem(model); %#ok<NASGU>

            try
                step = get_param(model, "CompiledStepSize");
                if string(step) == "auto"
                    error("Step size 'auto' not supported");
                end
                sampleTime = sprintf("%.17e", evalin("base", step));
            catch
                error("CIGRE:CodeDescriptor:StepSizeNotCalculated", ...
                    "Step size could not be evaluated for model '%s'", model);
            end

            metadata = cigre.description.ModelMetadata(...
                "SystemTargetFile", erase(get_param(model, "SystemTargetFile"), ".tlc"), ...
                "ModelVersion",     get_param(model, "ModelVersion"), ...
                "Description",      get_param(model, "Description"), ...
                "SampleTime",       sampleTime, ...
                "CreatedBy",        get_param(model, "Creator"), ...
                "CreatedOn",        get_param(model, "Created"), ...
                "ModifiedBy",       get_param(model, "LastModifiedBy"), ...
                "ModifiedOn",       get_param(model, "LastModifiedDate"), ...
                "ModelModifiedComment", get_param(model, "ModifiedComment"), ...
                "ModelModifiedHistory", get_param(model, "ModifiedHistory"));
        end

        function code = getWrapperHeaderCode(obj)
            % Return the generated wrapper header (.h) as a string array of lines.
            code = obj.readWrapperFile(".h");
        end

        function code = getWrapperSourceCode(obj)
            % Return the generated wrapper source (.c) as a string array of lines.
            code = obj.readWrapperFile(".c");
        end

        function vars = getInports(obj)
            % Return Variable array for the wrapper model inport signals.
            desc = obj.getCIGREDescriptor();
            inports = desc.getDataInterfaces("Inports");
            inports = removeUnimplemented(inports);
            vars = cigre.description.Variable.fromDataInterface(inports, obj.ModelName_);
        end

        function vars = getOutports(obj)
            % Return Variable array for the wrapper model outport signals.
            desc = obj.getCIGREDescriptor();
            outports = desc.getDataInterfaces("Outports");
            outports = removeUnimplemented(outports);
            vars = cigre.description.Variable.fromDataInterface(outports, obj.ModelName_);
        end

        function vars = getParameters(obj)
            % Return Variable array for the referenced model parameters.
            desc = obj.getModelDescriptor();
            parameters = desc.getDataInterfaces("Parameters");
            vars = cigre.description.Variable.fromDataInterface(parameters, obj.ModelName_);
        end

        function [internalVars, inputVars, outputVars] = getCodeInfoVariables(obj)
            % Extract and partition the InternalData from codeInfo.mat into three
            % Variable arrays: internal state variables, external inputs, and
            % external outputs.
            %
            % The RTM struct variable is included in internalVars — callers should
            % use getRTMStruct on ModelDescription to separate it after assignment.
            codeInfo = obj.getCodeInfo();
            internalData = codeInfo.InternalData;

            simulinkNames = strings(1, numel(internalData));
            externalNames = strings(1, numel(internalData));
            for i = 1:numel(internalData)
                simulinkNames(i) = cigre.description.Variable.extractSimulinkName(internalData(i));
                externalNames(i) = cigre.description.Variable.extractExternalName(internalData(i));
            end

            % Remove Simulink-internal bookkeeping fields that are not part of
            % model state and should not appear in the CIGRE DLL interface.
            isBookkeeping = externalNames == "rt_errorStatus" ...
                | externalNames == "timingBridge" ...
                | contains(externalNames, "mdlref_TID");
            internalData(isBookkeeping) = [];
            simulinkNames(isBookkeeping) = [];
            externalNames(isBookkeeping) = [];

            externalNames = applyReservedNameFallbacks(externalNames);

            types = strings(1, numel(internalData));
            pointers = strings(1, numel(internalData));
            for i = 1:numel(internalData)
                [types(i), pointers(i)] = cigre.description.Variable.extractType(internalData(i));
            end

            % Ensure all variables have at least one pointer level as required
            % by the generated C calling conventions.
            pointers(pointers == "") = "*";

            graphicalNames = string({internalData.GraphicalName});
            isInput    = graphicalNames == "ExternalInput";
            isOutput   = graphicalNames == "ExternalOutput";
            isInternal = ~isInput & ~isOutput;

            inputVars = cigre.description.Variable.create(...
                "SimulinkName", simulinkNames(isInput), ...
                "ExternalName", externalNames(isInput), ...
                "Type",         types(isInput), ...
                "Pointers",     pointers(isInput));
            outputVars = cigre.description.Variable.create(...
                "SimulinkName", simulinkNames(isOutput), ...
                "ExternalName", externalNames(isOutput), ...
                "Type",         types(isOutput), ...
                "Pointers",     pointers(isOutput));
            internalVars = cigre.description.Variable.create(...
                "SimulinkName", simulinkNames(isInternal), ...
                "ExternalName", externalNames(isInternal), ...
                "Type",         types(isInternal), ...
                "Pointers",     pointers(isInternal));
        end

        function iface = getInitializeInterface(obj)
            % Return the FunctionInterface for the wrapper's Initialize function.
            desc = obj.getCIGREDescriptor();
            raw = desc.getFunctionInterfaces("Initialize");
            iface = cigre.description.FunctionInterface.fromCoderFunctionInterface(raw);
        end

        function iface = getOutputInterface(obj)
            % Return the FunctionInterface for the wrapper's Output (step) function.
            desc = obj.getCIGREDescriptor();
            raw = desc.getFunctionInterfaces("Output");
            iface = cigre.description.FunctionInterface.fromCoderFunctionInterface(raw);
        end

        function iface = getTerminateInterface(obj)
            % Return the FunctionInterface for the referenced model's Terminate function.
            desc = obj.getModelDescriptor();
            raw = desc.getFunctionInterfaces("Terminate");
            iface = cigre.description.FunctionInterface.fromCoderFunctionInterface(raw);
        end

        function iface = getModelRefInitializeInterface(obj)
            % Return the FunctionInterface for the model reference Initialize function,
            % used to support snapshot restart. Handles both the pre-R2022b (parse from
            % source) and post-R2022b (getServiceFunctionPrototype) descriptor APIs.
            model = obj.CIGREInterfaceName_;
            desc = obj.getCIGREDescriptor();

            if verLessThan("MATLAB", "9.14")
                iface = cigre.description.FunctionInterface.fromSourceFile(...
                    desc.BuildDir, model, "Initialize");
            else
                raw = desc.getServiceFunctionPrototype(model + "_Initialize");
                iface = cigre.description.FunctionInterface.fromServiceFunctionPrototype(raw);
            end
        end

        function delete(obj)
            % Release any file locks held by cached code descriptor objects.
            if ~isempty(obj.CIGREDescriptor_) && isvalid(obj.CIGREDescriptor_)
                delete(obj.CIGREDescriptor_);
            end
            if ~isempty(obj.ModelDescriptor_) && isvalid(obj.ModelDescriptor_)
                delete(obj.ModelDescriptor_);
            end
        end

    end

    methods (Access = private)

        function desc = getCIGREDescriptor(obj)
            % Lazily initialise and cache the coder.CodeDescriptor for the wrapper.
            if isempty(obj.CIGREDescriptor_) || ~isvalid(obj.CIGREDescriptor_)
                obj.CIGREDescriptor_ = coder.getCodeDescriptor(obj.CIGREInterfaceName_);
            end
            desc = obj.CIGREDescriptor_;
        end

        function desc = getModelDescriptor(obj)
            % Lazily initialise and cache the coder.CodeDescriptor for the
            % referenced model. Parameters and Terminate come from this descriptor.
            if isempty(obj.ModelDescriptor_) || ~isvalid(obj.ModelDescriptor_)
                cigreDesc = obj.getCIGREDescriptor();
                obj.ModelDescriptor_ = getReferencedModelCodeDescriptor(...
                    cigreDesc, obj.ModelName_);
            end
            desc = obj.ModelDescriptor_;
        end

        function info = getCodeInfo(obj)
            % Lazily load and cache the codeInfo struct written by the RTW build.
            if isempty(obj.CodeInfo_)
                codeInfoPath = fullfile(obj.CodeGenFolder_, ...
                    obj.CIGREInterfaceName_ + "_cigre_rtw", "codeInfo.mat");
                obj.CodeInfo_ = load(codeInfoPath).codeInfo;
            end
            info = obj.CodeInfo_;
        end

        function code = readWrapperFile(obj, extension)
            % Read a generated wrapper file (.h or .c) as a string array of lines.
            filePath = fullfile(obj.CodeGenFolder_, ...
                obj.CIGREInterfaceName_ + "_cigre_rtw", ...
                obj.CIGREInterfaceName_ + extension);
            if ~isfile(filePath)
                error("CIGRE:CodeDescriptor:FileNotFound", ...
                    "No wrapper file found at '%s'", filePath);
            end
            code = readFromFile(filePath);
        end

    end
end

% --- Local helper functions -----------------------------------------------

function interfaces = removeUnimplemented(interfaces)
    % Remove data interfaces with no code implementation, which arise when a
    % port exists in the model but generates no corresponding C variable.
    isUnimplemented = arrayfun(@(x) isempty(x.Implementation), interfaces);
    interfaces(isUnimplemented) = [];
end

function names = applyReservedNameFallbacks(names)
    % Append a suffix to any name that clashes with reserved CIGRE interface
    % identifiers ("inputs"/"outputs") to prevent C struct field name conflicts.
    reserved = ["inputs", "outputs"];
    for i = 1:numel(names)
        names(i) = matlab.lang.makeUniqueStrings(names(i), reserved);
    end
end