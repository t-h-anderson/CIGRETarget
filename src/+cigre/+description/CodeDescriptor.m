classdef CodeDescriptor < handle
    % Wraps the Simulink coder.CodeDescriptor API, providing a mockable
    % boundary.
    
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

        function meta = getModelMetadata(obj)
            % Read model properties via get_param and return them as a plain
            % struct so callers have no dependency on the Simulink API.
            model = obj.ModelName_;
            cModel = util.loadSystem(model); %#ok<NASGU>

            meta.SystemTargetFile = erase(get_param(model, "SystemTargetFile"), ".tlc");
            meta.ModifiedBy = get_param(model, "LastModifiedBy");
            meta.ModifiedOn = get_param(model, "LastModifiedDate");
            meta.CreatedBy = get_param(model, "Creator");
            meta.CreatedOn = get_param(model, "Created");
            meta.Description = get_param(model, "Description");
            meta.ModelModifiedComment = get_param(model, "ModifiedComment");
            meta.ModelModifiedHistory = get_param(model, "ModifiedHistory");
            meta.ModelVersion = get_param(model, "ModelVersion");

            try
                step = get_param(model, "CompiledStepSize");
                if string(step) == "auto"
                    error("Step size 'auto' not supported");
                end
                meta.SampleTime = sprintf("%.17e", evalin("base", step));
            catch
                error("CIGRE:CodeDescriptor:StepSizeNotCalculated", ...
                    "Step size could not be evaluated for model '%s'", model);
            end
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
            id = codeInfo.InternalData;

            slname = strings(1, numel(id));
            externalName = strings(1, numel(id));
            for i = 1:numel(id)
                slname(i) = cigre.description.Variable.extractSimulinkName(id(i));
                externalName(i) = cigre.description.Variable.extractExternalName(id(i));
            end

            % Remove Simulink-internal bookkeeping fields that are not part of
            % model state and should not appear in the CIGRE DLL interface.
            isBookkeeping = externalName == "rt_errorStatus" ...
                | externalName == "timingBridge" ...
                | contains(externalName, "mdlref_TID");
            id(isBookkeeping) = [];
            slname(isBookkeeping) = [];
            externalName(isBookkeeping) = [];

            externalName = applyReservedNameFallbacks(externalName);

            type = strings(1, numel(id));
            pointers = strings(1, numel(id));
            for i = 1:numel(id)
                [type(i), pointers(i)] = cigre.description.Variable.extractType(id(i));
            end

            % Ensure all variables have at least one pointer level as required
            % by the generated C calling conventions.
            pointers(pointers == "") = "*";

            graphicalNames = string({id.GraphicalName});
            idxInput = graphicalNames == "ExternalInput";
            idxOutput = graphicalNames == "ExternalOutput";
            idxInternal = ~idxInput & ~idxOutput;

            inputVars = cigre.description.Variable.create(...
                "SimulinkName", slname(idxInput), ...
                "ExternalName", externalName(idxInput), ...
                "Type", type(idxInput), ...
                "Pointers", pointers(idxInput));
            outputVars = cigre.description.Variable.create(...
                "SimulinkName", slname(idxOutput), ...
                "ExternalName", externalName(idxOutput), ...
                "Type", type(idxOutput), ...
                "Pointers", pointers(idxOutput));
            internalVars = cigre.description.Variable.create(...
                "SimulinkName", slname(idxInternal), ...
                "ExternalName", externalName(idxInternal), ...
                "Type", type(idxInternal), ...
                "Pointers", pointers(idxInternal));
        end

        function iface = getInitializeInterface(obj)
            % Return the FunctionInterface for the wrapper's Initialize function.
            desc = obj.getCIGREDescriptor();
            raw = desc.getFunctionInterfaces("Initialize");
            iface = convertFunctionInterface(raw);
        end

        function iface = getOutputInterface(obj)
            % Return the FunctionInterface for the wrapper's Output (step) function.
            desc = obj.getCIGREDescriptor();
            raw = desc.getFunctionInterfaces("Output");
            iface = convertFunctionInterface(raw);
        end

        function iface = getTerminateInterface(obj)
            % Return the FunctionInterface for the referenced model's Terminate function.
            desc = obj.getModelDescriptor();
            raw = desc.getFunctionInterfaces("Terminate");
            iface = convertFunctionInterface(raw);
        end

        function iface = getModelRefInitializeInterface(obj)
            % Return the FunctionInterface for the model reference Initialize function,
            % used to support snapshot restart. Handles both the pre-R2022b (parse from
            % source) and post-R2022b (getServiceFunctionPrototype) descriptor APIs.
            model = obj.CIGREInterfaceName_;
            desc = obj.getCIGREDescriptor();

            if verLessThan("MATLAB", "9.14")
                iface = parseModelRefInitFromSource(desc, model, "Initialize");
            else
                raw = desc.getServiceFunctionPrototype(model + "_Initialize");
                iface = convertServiceFunctionPrototype(raw);
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
            if ~isempty(obj.CodeInfo_) && isvalid(obj.CodeInfo_)
                delete(obj.CodeInfo_);
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
            here = obj.CodeGenFolder_;
            wrapper = obj.CIGREInterfaceName_;
            filePath = fullfile(here, wrapper + "_cigre_rtw", wrapper + extension);
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
    idx = arrayfun(@(x) isempty(x.Implementation), interfaces);
    interfaces(idx) = [];
end

function names = applyReservedNameFallbacks(names)
    % Append a suffix to any name that clashes with reserved CIGRE interface
    % identifiers ("inputs"/"outputs") to prevent C struct field name conflicts.
    reserved = ["inputs", "outputs"];
    for i = 1:numel(names)
        names(i) = matlab.lang.makeUniqueStrings(names(i), reserved);
    end
end

function iface = convertFunctionInterface(raw)
    % Convert a coder.FunctionInterface to a FunctionInterface value object.
    if isempty(raw)
        iface = cigre.description.FunctionInterface();
        return
    end

    name = string(raw.Prototype.Name);
    args = raw.ActualArgs;
    nArgs = args.Size;

    argNames = strings(1, nArgs);
    argTypes = strings(1, nArgs);
    argPointers = strings(1, nArgs);
    for i = 1:nArgs
        argNames(i) = cigre.description.Variable.extractSimulinkName(args(i));
        [argTypes(i), argPointers(i)] = cigre.description.Variable.extractType(args(i));
    end

    iface = cigre.description.FunctionInterface(...
        "Name", name, ...
        "ArgumentNames", argNames, ...
        "ArgumentTypes", argTypes, ...
        "ArgumentPointers", argPointers);
end

function iface = convertServiceFunctionPrototype(raw)
    % Convert a coder.ServiceFunctionPrototype (MATLAB >= R2022b) to a
    % FunctionInterface value object.
    if isempty(raw)
        iface = cigre.description.FunctionInterface();
        return
    end

    args = raw.Arguments.toArray();
    argNames = string({args.Name});
    [argTypes, argPointers] = cigre.description.Variable.extractBaseType(...
        struct("Implementation", args));

    iface = cigre.description.FunctionInterface(...
        "Name", string(raw.Name), ...
        "ArgumentNames", argNames, ...
        "ArgumentTypes", argTypes, ...
        "ArgumentPointers", argPointers);
end

function iface = parseModelRefInitFromSource(desc, model, type)
    % Parse the model reference initialize function signature by reading the
    % generated C source directly. Used for MATLAB versions before R2022b that
    % do not support getServiceFunctionPrototype.
    sourceFile = model + ".c";
    f = readFromFile(fullfile(desc.BuildDir, sourceFile));

    idxStart = find(contains(f, "void " + model + "_" + type + "("), 1);

    if isempty(idxStart)
        iface = cigre.description.FunctionInterface();
        return
    end

    % Signature may span multiple lines — collect until the closing parenthesis.
    sigLines = f(idxStart:end);
    idxEnd = find(contains(sigLines, ")"), 1);
    sigText = strjoin(sigLines(1:idxEnd), "");

    funcName = extractBetween(sigText, " ", "(");
    argsText = extractBetween(sigText, "(", ")");
    argTokens = strtrim(strsplit(argsText, ","));

    nArgs = numel(argTokens);
    argNames = strings(1, nArgs);
    argTypes = strings(1, nArgs);
    argPointers = strings(1, nArgs); % TODO: extract pointer level from token

    for i = 1:nArgs
        parts = strsplit(argTokens(i), " ");
        argTypes(i) = parts(1);
        argNames(i) = erase(parts(2), "*");
    end

    iface = cigre.description.FunctionInterface(...
        "Name", funcName, ...
        "ArgumentNames", argNames, ...
        "ArgumentTypes", argTypes, ...
        "ArgumentPointers", argPointers);
end