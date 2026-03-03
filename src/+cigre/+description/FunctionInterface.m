classdef FunctionInterface
    % Represents a C function prototype extracted from the Simulink code
    % descriptor. Returned by CodeDescriptor methods so that ModelDescription
    % has no direct dependency on coder.descriptor types.
    %
    % An empty interface (Name == "") signals that no function was found,
    % avoiding the need for callers to handle [] vs object.
    %
    % Static factory methods convert the three Simulink representations:
    %   fromCoderFunctionInterface   - coder.FunctionInterface (all MATLAB versions)
    %   fromServiceFunctionPrototype - coder.ServiceFunctionPrototype (>= R2022b)
    %   fromSourceFile               - parses the .c source directly (< R2022b)

    properties
        Name (1,1) string = ""
        ArgumentNames (1,:) string = string.empty(1,0)
        ArgumentTypes (1,:) string = string.empty(1,0)
        ArgumentPointers (1,:) string = string.empty(1,0)
    end

    properties (Dependent)
        IsEmpty (1,1) logical
    end

    methods
        function obj = FunctionInterface(nvp)
            arguments
                nvp.Name (1,1) string = ""
                nvp.ArgumentNames (1,:) string = string.empty(1,0)
                nvp.ArgumentTypes (1,:) string = string.empty(1,0)
                nvp.ArgumentPointers (1,:) string = string.empty(1,0)
            end
            obj.Name = nvp.Name;
            obj.ArgumentNames = nvp.ArgumentNames;
            obj.ArgumentTypes = nvp.ArgumentTypes;
            obj.ArgumentPointers = nvp.ArgumentPointers;
        end

        function val = get.IsEmpty(obj)
            val = obj.Name == "";
        end
    end
    methods (Static)

        function iface = fromCoderFunctionInterface(raw)
            % Convert a coder.FunctionInterface to a FunctionInterface.
            % Returns an empty FunctionInterface when raw is empty, i.e. when
            % the requested function does not exist in the generated code.
            arguments
                raw (1,:) coder.descriptor.FunctionInterface {mustBeScalarOrEmpty}
            end

            if isempty(raw)
                iface = cigre.description.FunctionInterface();
                return
            end

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
                "Name", string(raw.Prototype.Name), ...
                "ArgumentNames", argNames, ...
                "ArgumentTypes", argTypes, ...
                "ArgumentPointers", argPointers);
        end

        function iface = fromServiceFunctionPrototype(raw)
            % Convert a coder.ServiceFunctionPrototype to a FunctionInterface.
            % The ServiceFunctionPrototype API was introduced in R2022b (v9.14)
            % and is the preferred path for model-reference init functions.
            % Returns an empty FunctionInterface when raw is empty.
            arguments
                raw (1,:) coder.descriptor.types.Prototype {mustBeScalarOrEmpty}
            end

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

        function iface = fromSourceFile(buildDirectory, modelName, functionType)
            % Parse a model-reference initialize function signature directly
            % from the generated C source. Used for MATLAB versions before
            % R2022b that do not support getServiceFunctionPrototype.
            %
            % buildDirectory - folder containing the generated .c file
            % modelName      - base name of the model, determines the filename
            %                  and expected function name prefix
            % functionType   - function suffix to search for, e.g. "Initialize"
            arguments
                buildDirectory (1,1) string
                modelName (1,1) string
                functionType (1,1) string
            end

            sourceLines = readFromFile(fullfile(buildDirectory, modelName + ".c"));
            searchToken = "void " + modelName + "_" + functionType + "(";
            signatureStart = find(contains(sourceLines, searchToken), 1);

            if isempty(signatureStart)
                iface = cigre.description.FunctionInterface();
                return
            end

            % The signature may span multiple lines — collect until ")"
            signatureLines = sourceLines(signatureStart:end);
            signatureEnd = find(contains(signatureLines, ")"), 1);
            signatureText = strjoin(signatureLines(1:signatureEnd), "");

            functionName = extractBetween(signatureText, " ", "(");
            argsText = extractBetween(signatureText, "(", ")");
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
                "Name", functionName, ...
                "ArgumentNames", argNames, ...
                "ArgumentTypes", argTypes, ...
                "ArgumentPointers", argPointers);
        end

    end

end