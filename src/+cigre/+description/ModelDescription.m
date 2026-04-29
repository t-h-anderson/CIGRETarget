classdef ModelDescription < handle
    %MODELDESCRIPTION

    properties
        MaxExternalIdentifier (1,1) double = 31
    end

    properties
        CodeGenFolder
        WorkFolder
    end

    % Model metadata properties
    properties
        ModelName (1,1) string      % Top level model to be built
        CIGREInterfaceName (1,1) string        % Top level wrapper defining the interface between ert and cigre

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
        % Simulink code generator prefixes on output/input port argument names
        SimulinkOutputPortPrefix (1,1) string = "rty_"
        SimulinkInputPortPrefix (1,1) string = "rtx_"

        % Patterns used to identify the RTM struct variable in InternalData
        RtmVarSuffix (1,1) string = "_M"
        RtmVarFallback (1,1) string = "MODEL"
        RtmVarTypeFallback (1,1) string = "RT_MODEL_"
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
        HasTimingBridge
        HasInitFunction
        HasRateScheduler

        % The leaves of any nested parameters
        CIGREParameters
        NumCigreParameters % Extra for structs and arrays
    end

    properties (Access = protected)
        CIGREInterfaceDescriptor_
        ModelCodeDescriptor_

        CIGREInterfaceCodeInfo_
    end

    methods
        function obj = ModelDescription(modelName, nvp)
            arguments
                modelName (1,1) string
                nvp.CIGREInterfaceName (1,1) string = string(missing)
                nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
                nvp.WorkFolder (1,1) string = Simulink.fileGenControl('getConfig').CacheFolder
            end

            obj.ModelName = modelName;
            obj.CIGREInterfaceName = nvp.CIGREInterfaceName;
            obj.CodeGenFolder = nvp.CodeGenFolder;
            obj.WorkFolder = nvp.WorkFolder;
        end

        function analyse(obj, descriptor)
            arguments
                obj
                descriptor (1,1) cigre.description.ICodeDescriptor
            end
            % Populate this description from the given CodeDescriptor. The
            % descriptor owns all Simulink/coder/file I/O

            % Model metadata
            metadata = descriptor.getModelMetadata();
            obj.SystemTargetFile = metadata.SystemTargetFile;
            obj.ModifiedBy = metadata.ModifiedBy;
            obj.ModifiedOn = metadata.ModifiedOn;
            obj.CreatedBy = metadata.CreatedBy;
            obj.CreatedOn = metadata.CreatedOn;
            obj.Description = metadata.Description;
            obj.ModelModifiedComment = metadata.ModelModifiedComment;
            obj.ModelModifiedHistory = metadata.ModelModifiedHistory;
            obj.ModelVersion = metadata.ModelVersion;
            obj.SampleTime = metadata.SampleTime;

            % Parse code structure from the generated wrapper files
            headerCode = descriptor.getWrapperHeaderCode();
            sourceCode = descriptor.getWrapperSourceCode();

            % Extract RTM struct pointer field names from the FULL (unstripped)
            % header before processRTMStructCode discards them. These names are
            % the reliable discriminator for classifyRTMFields: a variable is an
            % RTM pointer field iff its ERTName appears in this list.
            rtmFieldNames = cigre.description.ModelDescription.parseRTMStructFieldNames(headerCode);

            [obj.TimingBridgeCode, obj.NumberOfTasks] = ...
                cigre.description.ModelDescription.processRTMStructCode(headerCode);
            obj.InitializeOnlyCode = ...
                cigre.description.ModelDescription.processInitializeCode(sourceCode);
            obj.RateSchedulerCode = ...
                cigre.description.ModelDescription.processRateSchedulerCode(sourceCode, obj.CIGREInterfaceName);

            % Internal state variables — must come before function interfaces
            % because translateNames relies on InternalData/InputData/OutputData
            [internalVars, inputVars, outputVars] = descriptor.getCodeInfoVariables();
            obj.InputData = inputVars;
            obj.OutputData = outputVars;
            obj.InternalData = internalVars;
            obj.getRTMStruct();

            % Data interfaces
            obj.Inputs = descriptor.getInports();
            obj.Outputs = descriptor.getOutports();
            obj.Parameters = descriptor.getParameters();

            % Function call signatures for the four CIGRE entry points
            obj.loadModelRefInitialiseFunctionInterface(descriptor);
            obj.loadInitialiseFunctionInterface(descriptor);
            obj.loadStepFunctionInterface(descriptor);
            obj.loadTerminateFunctionInterface(descriptor);

            % Phase 2: classify remaining InternalData into RTM pointer fields
            % vs. standalone variables. Name-based matching against the header
            % is primary; step-arg type matching is the fallback when the header
            % contains no RTM struct definition (e.g. minimal mock headers in tests).
            obj.classifyRTMFields(rtmFieldNames);
        end

        function writeDLLSource(obj, writer, nvp)
            arguments
                obj (1,1) cigre.description.ModelDescription
                writer (1,1) cigre.writer.CIGREWriter
                nvp.ParameterConfig (1,1) cigre.config.ParameterConfiguration = cigre.config.ParameterConfiguration()
            end

            [dllText, cFile] = writer.writeDLL(obj, "ParameterConfig", nvp.ParameterConfig);
            [headerText, hFile] = writer.writeHeader(obj, "ParameterConfig", nvp.ParameterConfig);

            buildDir = fullfile(obj.CodeGenFolder, "slprj", "cigre");

            writeToFile(dllText, fullfile(buildDir, cFile));
            writeToFile(headerText, fullfile(buildDir, hFile));
        end

    end

    methods (Access = private)

        function getRTMStruct(obj)
            % Phase 1 of RTM classification: find the RTM struct variable,
            % record its type, and remove it from InternalData.
            % RTMStruct is populated later by classifyRTMFields once the
            % step function interface is available for discrimination.
            internalNames = string({obj.InternalData.ERTName});
            idx = find(endsWith(internalNames, cigre.description.ModelDescription.RtmVarSuffix + textBoundaryPattern), 1);
            if isempty(idx)
                idx = find(contains(internalNames, cigre.description.ModelDescription.RtmVarFallback, "IgnoreCase", true), 1);
            end

            if isempty(idx)
                types = string({obj.InternalData.Type});
                idx = find(contains(types, cigre.description.ModelDescription.RtmVarTypeFallback, "IgnoreCase", true), 1);
            end
            
            if isempty(idx)
                error("CIGRE:ModelDescription:RTMStructNotFound", ...
                    "Could not identify the Real-Time Model struct in the internal data for model '%s'. " + ...
                    "Expected a variable ending in '_M' or containing 'MODEL'.", obj.ModelName);
            end

            obj.RTMVarType = obj.InternalData(idx).Type;
            obj.InternalData(idx) = [];
        end

        function classifyRTMFields(obj, rtmFieldNames)
            % Phase 2 of RTM classification: populate RTMStruct with the subset
            % of InternalData entries that are pointer fields of the RTM struct.
            %
            % Primary path — name-based matching (rtmFieldNames non-empty):
            %   A variable is an RTM pointer field iff its ERTName appears
            %   in the set of pointer field names parsed from the wrapper header.
            %   This correctly handles cases where two variables share the same
            %   C type (e.g. a global InstP instance and the RTM InstP pointer
            %   field) that cannot be distinguished by type alone.
            %
            % Fallback path — step-arg type matching (rtmFieldNames empty):
            %   Variables whose type appears in the step function argument list
            %   are standalone; the rest are assumed to be RTM pointer fields.
            %   Used when the header contains no RTM struct definition (e.g.
            %   minimal mock headers in unit tests).
            if isempty(obj.InternalData)
                obj.RTMStruct = obj.InternalData;
                return
            end

            if ~isempty(rtmFieldNames)
                internalNames = string([obj.InternalData.ERTName]);
                isRTMField = ismember(internalNames, rtmFieldNames);
                obj.RTMStruct = obj.InternalData(isRTMField);
                return
            end

            % Fallback: classify by step-arg type exclusion
            if isempty(obj.StepInputs)
                obj.RTMStruct = obj.InternalData;
                return
            end
            stepArgTypes  = string([obj.StepInputs.Type]);
            internalTypes = string([obj.InternalData.Type]);
            obj.RTMStruct = obj.InternalData(~ismember(internalTypes, stepArgTypes));
        end

        function loadModelRefInitialiseFunctionInterface(obj, descriptor)
            iface = descriptor.getModelRefInitializeInterface();
            [obj.ModelRefInitialiseName, obj.ModelRefInitialiseInputs] = ...
                obj.processInterface(iface);
        end

        function loadInitialiseFunctionInterface(obj, descriptor)
            iface = descriptor.getInitializeInterface();
            [obj.InitializeName, obj.InitialiseInputs] = obj.processInterface(iface);
        end

        function loadStepFunctionInterface(obj, descriptor)
            iface = descriptor.getOutputInterface();
            [obj.StepName, obj.StepInputs] = obj.processInterface(iface);
        end

        function loadTerminateFunctionInterface(obj, descriptor)
            iface = descriptor.getTerminateInterface();
            [obj.TerminateName, obj.TerminateInputs] = obj.processInterface(iface);
        end

        function [name, inputs] = processInterface(obj, iface)
            % Convert a FunctionInterface into a name and Variable array,
            % resolving argument names via translateNames.
            if isempty(iface) || iface.IsEmpty
                name = "";
                inputs = cigre.description.Variable.empty(1,0);
                return
            end

            argNames = obj.translateNames(iface.ArgumentNames, iface.ArgumentTypes);
            name = iface.Name;
            inputs = cigre.description.Variable.create(...
                "ERTName", argNames, ...
                "Type", iface.ArgumentTypes, ...
                "Pointers", iface.ArgumentPointers);
        end

        function inputNames = translateNames(obj, inputNames, inputTypes)
            arguments
                obj
                inputNames (1,:) string
                inputTypes (1,:) string
            end
            % Resolve C argument names from their types using the known internal,
            % input, and output data variables. The RTM struct is handled as a
            % special case since it is not a data variable.

            knownTypes = string([obj.InternalData.Type obj.InputData.Type obj.OutputData.Type]);
            knownNames = string([obj.InternalData.ERTName obj.InputData.ERTName obj.OutputData.ERTName]);

            % Strip graphical port prefixes added by Simulink code generation
            inputNames = erase(inputNames, [cigre.description.ModelDescription.SimulinkOutputPortPrefix, cigre.description.ModelDescription.SimulinkInputPortPrefix]);
            portERTNames = string([[obj.Inputs.ERTName], [obj.Outputs.ERTName]]);
            for i = 1:numel(inputNames)
                idx = ismember(portERTNames, inputNames(i));
                if any(idx)
                    inputNames(i) = portERTNames(idx);
                end
            end

            for i = 1:numel(inputTypes)
                if isempty(inputTypes(i))
                    continue
                end

                % The RTM type is an opaque model handle, not a data variable —
                % resolve it to the fixed struct name without searching knownTypes
                if inputTypes(i) == obj.RTMVarType
                    inputNames(i) = obj.RTMStructName;
                    continue
                end

                idx = ismember(knownTypes, inputTypes(i));
                if sum(idx) == 1
                    inputNames(i) = knownNames(idx);
                else
                    warning("CIGRE:ModelDescription:UnknownType", ...
                        "'%s' could not be resolved to a known variable name", inputTypes(i));
                end
            end
        end

    end

    methods % Dependent

        function value = get.HasTimingBridge(obj)
            value = contains(obj.TimingBridgeCode, "timingBridge");
        end

        function value = get.HasInitFunction(obj)
            value = obj.ModelRefInitialiseName ~= "";
        end

        function value = get.HasRateScheduler(obj)
            value = obj.RateSchedulerCode ~= "";
        end

        function value = get.CIGREParameters(obj)
            leaves = obj.Parameters.getLeaves();
            value = leaves([]);
            names = string.empty(1,0);
            for i = 1:numel(leaves)
                leaf = leaves(i);
                nData = numel(leaf.DefaultValue);
                for j = 1:nData
                    thisParam = leaf;
                    thisParam.DefaultValue = leaf.DefaultValue(j);
                    thisParam.CIGREName = matlab.lang.makeUniqueStrings(leaf.CIGREName, names);
                    thisParam.Dimensions = 1;
                    if nData > 1
                        % Convert to C-style base 0 indexing
                        cIdx = (j-1);
                        thisParam.SimulinkName = thisParam.SimulinkName + "[" + cIdx + "]";
                        thisParam.ERTName = thisParam.ERTName + "[" + cIdx + "]";
                    end
                    names = [names, thisParam.CIGREName]; %#ok<AGROW>
                    value(end+1) = thisParam; %#ok<AGROW>
                end
            end
        end

        function value = get.NumCigreParameters(obj)
            parameterDefaultVal = {obj.CIGREParameters.DefaultValue}';
            value = sum(cellfun(@(x) numel(x), parameterDefaultVal));
        end

    end

    methods (Static)

        function fieldNames = parseRTMStructFieldNames(headerCode)
            % Extract the names of pointer fields declared inside the RTM
            % struct (``struct tag_...``) from the wrapper header.
            %
            % These names are the authoritative discriminator for
            % classifyRTMFields: an InternalData variable whose ERTName
            % appears in this set is a pointer field of the RTM struct and
            % must be wired via RTMStructName->field = field in the generated
            % DLL source. Variables absent from the set are standalone heap
            % allocations passed directly as step/init arguments.
            %
            % The method matches lines of the form
            %   <type> *<identifier>;
            % and returns <identifier>. Non-pointer fields (e.g. errorStatus
            % which is ``const char_T *errorStatus``) are also matched but
            % are harmless because they never appear in InternalData.
            arguments
                headerCode (:,1) string
            end

            if isscalar(headerCode)
                headerCode = strsplit(headerCode, newline)';
            end

            fieldNames = string.empty(1, 0);

            idxStart = find(contains(headerCode, "struct tag_"), 1);
            if isempty(idxStart)
                return
            end

            idxEnd = findLineStartText(headerCode, "}");
            idxEnd = idxEnd(find(idxEnd > idxStart, 1));
            if isempty(idxEnd)
                return
            end

            structLines = headerCode(idxStart:idxEnd);
            for i = 1:numel(structLines)
                tokens = regexp(structLines(i), '\*\s*(\w+)\s*;', 'tokens');
                if ~isempty(tokens)
                    fieldNames(end+1) = string(tokens{1}{1}); %#ok<AGROW>
                end
            end
        end

        function desc = analyseModel(model, cigreWrapper, nvp)
            arguments
                model (1,1) string
                cigreWrapper (1,1) string = cigre.internal.cigreWrap(model)
                nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
            end
            % Load models before constructing the descriptor so
            % coder.getCodeDescriptor can locate them. The cleanup objects
            % ensure both remain open for the duration of the analysis.
            cModel = util.loadSystem(model); %#ok<NASGU>
            cWrapper = util.loadSystem(cigreWrapper); %#ok<NASGU>

            descriptor = cigre.description.CodeDescriptor(...
                model, cigreWrapper, nvp.CodeGenFolder);
            desc = cigre.description.ModelDescription(model, ...
                "CIGREInterfaceName", cigreWrapper, ...
                "CodeGenFolder", nvp.CodeGenFolder);
            desc.analyse(descriptor);
        end

        function [tbc, nTasks] = processRTMStructCode(headerCode)
            arguments
                headerCode (:,1) string
            end

            if isscalar(headerCode)
                headerCode = strsplit(headerCode, newline)';
            end

            idxStart = find(contains(headerCode, "struct tag_"), 1);

            if ~isempty(idxStart)
                idxEnd = findLineStartText(headerCode, "}");
                idxEnd = idxEnd(find(idxEnd > idxStart, 1));

                code = headerCode(idxStart:idxEnd);

                if ~contains(code(1), "typedef")
                    code(1) = "typedef " + code(1);
                end
                code(end) = "}<<RTMStruct>>;";

                tmp = strjoin(code, newline);
                nTasksStr = extractBetween(tmp, "TID[", "]");

                tbc = code(1);

                if any(contains(code, "errorStatus"))
                    tbc = [tbc; "  const char_T *errorStatus;"];
                end

                if any(contains(code, "rtTimingBridge"))
                    tbc = [tbc; "  rtTimingBridge timingBridge;"];
                end

                if isempty(nTasksStr)
                    % Single-rate model — no TID array, no timing substructure
                    nTasks = 1;
                else
                    % Multi-rate model — embed the TID array and parse task count
                    nTasks = str2double(nTasksStr);
                    tbc = [tbc
                        "  /*"
                        "   * Timing:"
                        "   * The following substructure contains information regarding"
                        "   * the timing information for the model."
                        "   */"
                        "  struct {"
                        "    struct {"
                        "      uint32_T TID[" + nTasksStr + "];"
                        "    } TaskCounters;"
                        "  } Timing;"
                    ];
                end

                tbc = [tbc; code(end)];
                tbc = strjoin(tbc, newline);
            else
                % No RTM struct tag found — single-rate model with no timing bridge
                tbc = "";
                nTasks = 1;
            end
        end

        function code = processInitializeCode(srcCodeIn)
            arguments
                srcCodeIn (:,1) string
            end

            srcCode = srcCodeIn;
            if isscalar(srcCode)
                srcCode = strsplit(srcCode, newline)';
            end

            idxStart = find(contains(srcCode, "/* Model initialize function"));
            if numel(idxStart) > 1
                idxStart = idxStart(2); % first occurrence is the declaration
            end

            if ~isempty(idxStart)
                idxInitialize = find(contains(srcCode, "_initialize("), 1, "last");
                idxEnd = find(contains(srcCode, ");"));
                idxEnd = idxEnd(find(idxEnd > idxInitialize, 1));

                if isempty(idxEnd)
                    idxEnd = findLineStartText(srcCode, "}");
                end

                idxEnd = idxEnd(find(idxEnd > idxStart, 1));
                code = srcCode(idxStart:idxEnd);
                code = [code; "};"];
            else
                % Ensure there is always an initialize-only function
                code = ["{"; "};"];
            end

            % Rename to the _only variant so it can be called independently
            code(2) = insertAfter(code(2), "_initialize", "_only");
            code = strjoin(code, newline);
        end

        function code = processRateSchedulerCode(srcCodeIn, cigreInterfaceName)
            arguments
                srcCodeIn (:,1) string
                cigreInterfaceName (1,1) string
            end

            srcCode = srcCodeIn;
            if isscalar(srcCode)
                srcCode = strsplit(srcCode, newline)';
            end

            [~, idxStart] = findLineStartText(srcCode, "/*");
            idxStart = find(contains(srcCode, "rate_scheduler") & ~idxStart);
            if numel(idxStart) > 1
                idxStart = idxStart(2); % first occurrence is the declaration
            end

            if ~isempty(idxStart)
                idxEnd = findLineStartText(srcCode, "}");
                idxEnd = idxEnd(find(idxEnd > idxStart, 1));

                code = srcCode(idxStart:idxEnd);

                % Drop the old signature lines up to the closing ")" and
                % replace with the standardised RTMStruct-parameterised form
                idxSigEnd = find(contains(code, ")"), 1);
                code(1:idxSigEnd) = [];
                code = ["static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)"; code];

                if code(2) ~= "{"
                    code = [code(1); "{"; code(2:end)];
                end

                code = regexprep(code, cigreInterfaceName + cigre.description.ModelDescription.RtmVarSuffix, "RealTimeModel_M");
            else
                % Ensure there is always a rate scheduler stub
                code = [...
                    "static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)"
                    "{"
                    "}"];
            end

            % TODO: remove block IO references — they require a different include
            code(contains(code, "B_") | contains(code, "*blockIO")) = [];

            code = strjoin(code, newline);
        end

        function names = avoidReservedName(names)
            arguments
                names (1,:) string
            end
            % Append a suffix to any name that clashes with CIGRE interface
            % reserved identifiers to prevent C struct field name conflicts.
            reserved = cigre.description.ICodeDescriptor.ReservedCigreIdentifiers;
            for i = 1:numel(names)
                names(i) = matlab.lang.makeUniqueStrings(names(i), reserved);
            end
        end

    end

end

