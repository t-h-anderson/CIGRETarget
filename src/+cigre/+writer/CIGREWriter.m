classdef CIGREWriter
    %CIGREWRITER

    methods
        function obj = CIGREWriter()
        end
    end

    methods (Static)
        function [results, filename] = writeDLL(modelDescriptions, nvp)
            arguments
                modelDescriptions (1,1) cigre.description.ModelDescription
                nvp.DLLName = modelDescriptions.ModelName + "_CIGRE"
            end

            cigreSuffix = modelDescriptions.CIGRESuffix; 

            model = modelDescriptions.ModelName;
            cigreInterface = modelDescriptions.CIGREInterfaceName;

            results = readFromFile("TemplateWrapper.c");

            % Input
            inputNames = string({modelDescriptions.Inputs.Name}'); 
            
            % Output
            outputNames = string({modelDescriptions.Outputs.Name}');

             % Parameters
            paramNames = string({modelDescriptions.CIGREParameters.Name}'); % Path to param if in struct
            paramGraphicalNames = string({modelDescriptions.CIGREParameters.GraphicalName}'); % Parameter raw name
            paramTypes = repelem("", numel(paramNames));

            %% InitializeOnly
            initializeOnlyCode = modelDescriptions.InitializeOnlyCode;
            if initializeOnlyCode == ""
                initializeOnlyCode = "// No initialize code required";
            end
            results = strrep(results, "<<InitializeOnly>>", initializeOnlyCode);

            %% Replace wrapper header
            results = strrep(results, "<<CigreHeader>>", model + "_CIGRE.h");

            %% Heap definition
            heapdef = heapSize(modelDescriptions);
            results = strrep(results, "<<heap definition>>", heapdef);

            %% Strrep
            results = strrep(results, "<<CIGRE Suffix>>", cigreSuffix);

            %% Internal memory

            % Model in memory
            results = strrep(results, "<<RTMVarType>>", modelDescriptions.RTMVarType);
            results = strrep(results, "<<RTMStructName>>", modelDescriptions.RTMStructName);

            idx = 1;

            intStates = [modelDescriptions.InternalData, modelDescriptions.InputData modelDescriptions.OutputData];
            for i = 1:numel(intStates)
                intState = intStates(i);

                name = intState.Name;
                type = intState.Type;
                pointers = intState.Pointers;
                internalMalloc = type + pointers + " " + name + cigreSuffix + " = heap_malloc(&instance->IntStates[0], (int32_t)sizeof(" + type + "));";
                internalRestore = type + pointers + " " + name + cigreSuffix + " = (" + type + pointers + ")heap_get_address(&instance->IntStates[0], " + idx + ");";
                idx = idx + 1;

                internalMalloc = internalMalloc + newline + "    <<InternalStatesMalloc>>";
                internalRestore = internalRestore + newline + "    <<InternalStatesRestore>>";

                results = strrep(results, "<<InternalStatesMalloc>>", internalMalloc);
                results = strrep(results, "<<InternalStatesRestore>>", internalRestore);
            end

            results = strrep(results, "<<InternalStatesMalloc>>", "");
            results = strrep(results, "<<InternalStatesRestore>>", "");
            
            %% Map internal states
            internalStatesMap = ...
                "char errorStatus[255];" + newline ...
                + "    errorStatus[0] = '\0';" + newline ...
                + "    <<RTMStructName>>->errorStatus = errorStatus;" + newline;

            for i = 1:numel([modelDescriptions.RTMStruct.Name])
                internalStatesMap = internalStatesMap + newline ...
                    + "    " + "<<RTMStructName>>->" + modelDescriptions.RTMStruct(i).Name + " = " + modelDescriptions.RTMStruct(i).Name + ";" + newline;
            end

            results = strrep(results, "<<MapInternalStatesToModel>>", internalStatesMap);

            % Load Parameters
            paramMaps = "";
            params = modelDescriptions.Parameters;
            
            % Model arguments
            modelArgParams = params([params.IsModelArgument]);
            if numel(modelArgParams) > 0

                for i = 1:numel(modelArgParams)
                    modelArgParam = modelArgParams(i);
                    pName = modelArgParam.Name;
                    pGraphical = modelArgParam.GraphicalName;
                    paramMap = " = " + "parameters->" + pGraphical + ";" + newline;
                    structName = erase(modelArgParam.StorageSpecifier, "ModelArgument:");

                    paramMaps = paramMaps + ...
                        "<<RTMStructName>>->dwork->mdl_InstanceData.rtm." + structName + "->" + pName ... % Simulink structure
                        + paramMap; % CIGRE Memory
                end

            else
                paramMaps = paramMaps + "// No model argument parameters found" + newline + newline;
            end
            
            % Global params
            globalParams = params(~[params.IsModelArgument]);
            if ~isempty(globalParams)
                warning("Global parameters found:" + strjoin([globalParams.Name], ", ") + "." + newline ...
                    + "DLL may be non-deterministic when called in parallel. Instead, try to define all parameters as model arguments");
            end
            
            for i = 1:numel(globalParams)
                globalParam = globalParams(i);
                pName = globalParam.Name;
                pGraphical = globalParam.GraphicalName;
                
                paramMaps = paramMaps + ...
                    pName + " = " + "parameters->" + pGraphical + ";" + newline;
            end
            
            results = strrep(results, "<<MapParamsToModel>>", paramMaps);
           
            %% Cache internal states
            backupStatesMap = "";

            for i = 1:numel(modelDescriptions.RTMStruct)
                % DW_MyModel_wrap_T* dwork_backup;
                backupStatesMap = backupStatesMap + newline ...
                    + "    " + modelDescriptions.RTMStruct(i).Type + "* " + modelDescriptions.RTMStruct(i).Name + "_backup;";

                % dwork_backup = malloc(sizeof(DW_MyModel_wrap_T));
                backupStatesMap = backupStatesMap + newline ...
                    + "    " + modelDescriptions.RTMStruct(i).Name + "_backup = malloc(sizeof(" + modelDescriptions.RTMStruct(i).Type +"));";

                % *dwork_backup = *dwork;
                backupStatesMap = backupStatesMap + newline ...
                    + "    *" + modelDescriptions.RTMStruct(i).Name + "_backup = *" + modelDescriptions.RTMStruct(i).Name + ";";
            end
            results = strrep(results, "<<InternalStatesCache>>", backupStatesMap);

            %% Restore internal states
            restoreStatesMap = "";

            for i = 1:numel(modelDescriptions.RTMStruct)

                % *dwork = *dwork_backup;
                restoreStatesMap = restoreStatesMap + newline ...
                    + "    *" + modelDescriptions.RTMStruct(i).Name + " = *" + modelDescriptions.RTMStruct(i).Name + "_backup;";

                % dwork_backup = free(dworkbackup);
                restoreStatesMap = restoreStatesMap + newline ...
                    + "    free(" + modelDescriptions.RTMStruct(i).Name + "_backup);";

            end
            results = strrep(results, "<<InternalStatesRestoreFromCache>>", restoreStatesMap);


            % Replace IO struct names
            inputType = string([modelDescriptions.InputData.Type]);
            inputName = string([modelDescriptions.InputData.Name]);
            if isempty(inputType)
                results = strrep(results, "<<InputUnpack>>", " // No inputs");
                results = strrep(results, "<<ApplyInputData>>", " // No input data");
            else
                results = strrep(results, "<<InputUnpack>>", "<<InputType>>* inputs = (<<InputType>>*)instance->ExternalInputs;");
                results = strrep(results, "<<InputType>>", inputType);

                results = strrep(results, "<<ApplyInputData>>", "*<<InputName>> = *inputs;");
                results = strrep(results, "<<InputName>>", inputName);
            end

            outputType = string([modelDescriptions.OutputData.Type]);
            outputName = [modelDescriptions.OutputData.Name];
            if isempty(outputType)
                results = strrep(results, "<<OutputUnpack>>", " // No outputs");
                results = strrep(results, "<<ApplyOutputData>>", " // No output data");
            else
                results = strrep(results, "<<OutputUnpack>>", "<<OutputType>>* outputs = (<<OutputType>>*)instance->ExternalOutputs;");
                results = strrep(results, "<<OutputType>>", outputType);

                results = strrep(results, "<<ApplyOutputData>>", "*outputs = *<<OutputName>>;");
                results = strrep(results, "<<OutputName>>", outputName);
            end

            %% Parameter get
            params = modelDescriptions.Parameters;
            getIdx = (string([params.StorageSpecifier]) == "GetSet");
            getParams = params(getIdx);
            for i = 1:numel(getParams)
                getFn = getParams(i).GetMethod;
                type = "void";
                getFn = type + " " + getFn + "(){" + newline ...
                    + newline ...
                    + "};" + newline ...
                    + "<<ParamGetMethods>>";
                
                results = strrep(results, "<<ParamGetMethods>>", getFn);
            end
            results = strrep(results, "<<ParamGetMethods>>", "");
            
            %% Replace input pointers
            defineInputs = "&" + inputNames + cigreSuffix;
            defineInputs = strjoin(defineInputs, ", ");
            results = strrep(results, "<<InputPointers>>", defineInputs);

            %% Replace output pointers
            defineOutputs = "&" + outputNames + cigreSuffix;
            defineOutputs = strjoin(defineOutputs, ", ");
            results = strrep(results, "<<OutputPointers>>", defineOutputs);

            % Replace InputVariables
            defineInputs = inputNames + cigreSuffix;
            defineInputs = strjoin(defineInputs, ", ");
            results = strrep(results, "<<InputVariables>>", defineInputs);

            % Replace OutputVariables
            defineOutputs = outputNames + cigreSuffix;
            defineOutputs = strjoin(defineOutputs, ", ");
            results = strrep(results, "<<OutputVariables>>", defineOutputs);

            % Replace initialise
            modelInitialize = modelDescriptions.InitializeName;
            results = strrep(results, "<<ModelInitialize>>", modelInitialize);

            initialiseInputs = strjoin(string([modelDescriptions.InitialiseInputs.Name]) + cigreSuffix, ", ");
            results = strrep(results, "<<ModelInitialiseInputs>>", initialiseInputs);

           
            % Replace init
            if modelDescriptions.HasInitFunction
                init = "<<ModelInitFn>>(<<ModelInitInputs>>);";

                initInputs = strjoin(string([modelDescriptions.InitInputs.Name]) + cigreSuffix, ", "); % Handle of everything except model handle (first input)
                init = strrep(init, "<<ModelInitInputs>>", initInputs);

                modelInitialize = cigreInterface + "_Init";
                init = strrep(init, "<<ModelInitFn>>", modelInitialize);

            else
                init = "// No init function found";
            end

            results = strrep(results, "<<ModelInit>>", init);

            % Replace step
            modelStep = modelDescriptions.StepName;
            results = strrep(results, "<<ModelStep>>", modelStep);

            stepInputs = strjoin(string([modelDescriptions.StepInputs.Name]) + cigreSuffix, ", ");
            results = strrep(results, "<<ModelStepInputs>>", stepInputs);

            %% Set number of tasks
            results = strrep(results, "<<Number of tasks>>", string(modelDescriptions.NumberOfTasks));

            %% RTM Struct
            results = strrep(results, "<<RTMStructName>>", modelDescriptions.RTMStructName);
            results = strrep(results, "<<RTMType>>", modelDescriptions.RTMVarType);

            %% Model name
            results = strrep(results, "<<ModelName>>", model);

            % Wrapper name
            results = strrep(results, "<<WrapperName>>", cigreInterface);

            %% Write the results
            filename = nvp.DLLName + ".c";

        end

        function [results, filename] = writeHeader(modelDescriptions, nvp)
            arguments
                modelDescriptions cigre.description.ModelDescription
                nvp.DLLName = modelDescriptions.ModelName + "_CIGRE"
            end

            model = modelDescriptions.ModelName;
            cigreInterface = modelDescriptions.CIGREInterfaceName;

            cigreSuffix = modelDescriptions.CIGRESuffix;

            results = readFromFile("TemplateWrapper.h");

            % CIGRE Inputs
            inputNames = string([modelDescriptions.Inputs.Name]');
            inputTypes = [modelDescriptions.Inputs.Type]';
            inputDims = cellfun(@(x) string(prod(x)), {modelDescriptions.Inputs.Dimensions})';

            inputTypes = util.TranslateTypes.translateType(inputTypes, "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';

            % CIGRE Outputs
            outputNames = string([modelDescriptions.Outputs.Name]');
            outputTypes = [modelDescriptions.Outputs.Type]';

            outputTypes = util.TranslateTypes.translateType(outputTypes, "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';
            outputDims = cellfun(@(x) string(prod(x)), {modelDescriptions.Outputs.Dimensions})';

            %% Parameter get
            params = modelDescriptions.Parameters;
            getIdx = (string([params.StorageSpecifier]) == "GetSet");
            getParams = params(getIdx);
            for i = 1:numel(getParams)
                getFn = getParams(i).GetMethod;
                type = "void";
                getFn = type + " " + getFn + "();" + newline ...
                    + "<<ParamGetMethods>>";

                results = strrep(results, "<<ParamGetMethods>>", getFn);
            end
            results = strrep(results, "<<ParamGetMethods>>", "");

            % Parameters
            parameterNames = string([modelDescriptions.CIGREParameters.GraphicalName]');
            parameterTypes = [modelDescriptions.CIGREParameters.Type]';
            parameterMin = {modelDescriptions.CIGREParameters.Min}';
            parameterMax = {modelDescriptions.CIGREParameters.Max}';
            parameterDefaultVal = {modelDescriptions.CIGREParameters.DefaultValue}';

            parameterTypes = util.TranslateTypes.translateType(parameterTypes, "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';

            isHeader = isfile("./slprj/ert/_sharedutils/model_reference_types.h");
            if isHeader
                header = "#include ""model_reference_types.h""";
            else
                header = "";
            end
            results = strrep(results, "<<model_reference_types>>", header );

            %% Replace model header
            results = strrep(results, "<<WrapperHeader>>", cigreInterface + ".h");

            %% Strrep
            results = strrep(results, "<<CIGRE Suffix>>", cigreSuffix);

            %% Replace DefineInputs
            defineInputs = inputTypes + " " + inputNames + "[" + inputDims + "];";
            defineInputs = strjoin(defineInputs, newline);
            results = strrep(results, "<<DefineInputs>>", defineInputs);

            %% Replace Input Definition
            numInputs = numel(inputNames);
            results = strrep(results, "<<NumInputs>>", string(numInputs));

            inputTemplate = ...
                ["[<<Num>>] = {", ...
                "           .Name = ""<<InputName>>"",                                  // Input Signal name", ...
                "           .Description = ""<<InputDefinition>>"",                     // Description", ...
                "           .Unit = ""pu"",                                             // Units", ...
                "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<InputType>>, // Signal Type", ...
                "           .Width = <<InputWidth>>                                                  // Signal Dimension", ...
                "     }" ...
                ];

            inputTemplate = strjoin(inputTemplate, newline);

            % PSCAD has limited identifier length
            inputNames = erase(inputNames, textBoundaryPattern + "i_");
            externalInputNames = matlab.lang.makeUniqueStrings(inputNames, 1:numel(inputNames), modelDescriptions.MaxExternalIdentifier);

            inputDef = string.empty();
            for i = 1:numel(inputNames)
                inputDefI = inputTemplate;
                inputDefI = strrep(inputDefI, "<<Num>>", string(i-1));
                inputDefI = strrep(inputDefI, "<<InputName>>", externalInputNames(i));
                inputDefI = strrep(inputDefI, "<<InputDefinition>>", inputNames(i));
                inputDefI = strrep(inputDefI, "<<InputType>>", inputTypes(i));
                inputDefI = strrep(inputDefI, " <<InputWidth>>", inputDims(i));
                inputDef(i) = inputDefI;
            end

            inputDef = strjoin(inputDef, "," + newline);

            results = strrep(results, "<<InputDefinition>>", inputDef);

            %% Replace define outputs
            defineOutputs = outputTypes + " " + outputNames + "[" + outputDims + "];";
            defineOutputs = strjoin(defineOutputs, newline);
            results = strrep(results, "<<DefineOutputs>>", defineOutputs);

            %% Replace Output Definition
            numOutputs = numel(outputNames);
            results = strrep(results, "<<NumOutputs>>", string(numOutputs));

            outputTemplate = ...
                ["[<<Num>>] = {", ...
                "           .Name = ""<<OutputName>>"",                                  // Output Signal name", ...
                "           .Description = ""<<OutputDefinition>>"",                     // Description", ...
                "           .Unit = ""pu"",                                              // Units", ...
                "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<OutputType>>, // Signal Type", ...
                "           .Width = <<OutputWidth>>                                     // Signal Dimension", ...
                "      }" ...
                ];

            outputTemplate = strjoin(outputTemplate, newline);

            % PSCAD has limited identifier length
            outputNames = erase(outputNames, textBoundaryPattern + "o_");
            externalOutputNames = matlab.lang.makeUniqueStrings(outputNames, 1:numel(outputNames), modelDescriptions.MaxExternalIdentifier);

            outputDef = string.empty();
            for i = 1:numel(outputNames)
                outputDefI = outputTemplate;
                outputDefI = strrep(outputDefI, "<<Num>>", string(i-1));
                outputDefI = strrep(outputDefI, "<<OutputName>>", externalOutputNames(i));
                outputDefI = strrep(outputDefI, "<<OutputDefinition>>", outputNames(i));
                outputDefI = strrep(outputDefI, "<<OutputType>>", outputTypes(i));
                outputDefI = strrep(outputDefI, "<<OutputWidth>>", outputDims(i));

                outputDef(i) = outputDefI;
            end

            outputDef = strjoin(outputDef, "," + newline);

            results = strrep(results, "<<OutputDefinition>>", outputDef);

            %% Replace Parameter Definition
            numParameters = numel(parameterNames);
            results = strrep(results, "<<NumParam>>", string(numParameters));

            parameterTemplate = ...
                ["[<<Num>>] = {", ...
                "           .Name = ""<<ParamName>>"",                                  // Param  name", ...
                "           .Description = ""<<ParamDefinition>>"",                     // Description", ...
                "           .Unit = ""sec"",                                            // Units", ...
                "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<ParamType>>, // Signal Type", ...
                "           .FixedValue = 0,                                            // 0 for parameters which can be modified at any time, 1 for parameters which need to be defined at T0 but cannot be changed.", ...
                "           .DefaultValue.<<Val Type>> = <<Param Default Val>>,         // Default value", ...
                "           .MinValue.<<Val Type>> = <<Param Min>>,                     // Minimum value", ...
                "           .MaxValue.<<Val Type>> = <<Param Max>>                      // Maximum value", ...
                "      }" ...
                ];


            parameterTemplate = strjoin(parameterTemplate, newline);

            % PSCAD has limited identifier length
            externalParamNames = matlab.lang.makeUniqueStrings(parameterNames, 1:numel(parameterNames), modelDescriptions.MaxExternalIdentifier);

            paramDef = string.empty();
            for i = 1:numel(parameterNames)
                paramDefI = parameterTemplate;
                paramDefI = strrep(paramDefI, "<<Num>>", string(i-1));
                paramDefI = strrep(paramDefI, "<<ParamName>>", externalParamNames(i));
                paramDefI = strrep(paramDefI, "<<ParamDefinition>>", parameterNames(i));
                paramDefI = strrep(paramDefI, "<<ParamType>>", parameterTypes(i));

                valType = strrep(parameterTypes(i), "_T", "_Val");
                valType{1,1}(1) = upper(valType{1,1}(1));

                paramDefI = strrep(paramDefI, "<<Val Type>>", valType);

                paramMin = string(double(parameterMin{i}));
                paramDefI = strrep(paramDefI, "<<Param Min>>", paramMin);

                paramMax = string(double(parameterMax{i}));
                paramDefI = strrep(paramDefI, "<<Param Max>>", paramMax);

                paramDefault = string(double(parameterDefaultVal{i}));
                paramDefI = strrep(paramDefI, "<<Param Default Val>>", paramDefault);

                paramDef(i) = paramDefI;
            end

            paramDef = strjoin(paramDef, "," + newline);

            results = strrep(results, "<<ParameterDefinitions>>", paramDef);

            %% Replace define outputs
            defineParameters = parameterTypes + " " + parameterNames + ";";
            defineParameters = strjoin(defineParameters, newline);
            results = strrep(results, "<<DefineParameters>>", defineParameters);

            %% Model Version
            results = strrep(results, "<<ModelVersion>>", modelDescriptions.ModelVersion);

            %% Description
            results = strrep(results, "<<Description>>", modelDescriptions.Description);

            %% ModelCreatedDate
            results = strrep(results, "<<ModelCreatedDate>>", modelDescriptions.CreatedOn);

            %% ModelCreatedBy
            results = strrep(results, "<<ModelCreatedBy>>", modelDescriptions.CreatedBy);

            %% ModelModifiedOn
            results = strrep(results, "<<ModelModifiedOn>>", modelDescriptions.ModifiedOn);

            %% ModelModifiedBy
            results = strrep(results, "<<ModelModifiedBy>>", modelDescriptions.ModifiedBy);

            %% ModelModifiedComment
            results = strrep(results, "<<ModelModifiedComment>>", modelDescriptions.ModelModifiedComment);

            %% ModelHistory
            results = strrep(results, "<<ModelHistory>>", modelDescriptions.ModelModifiedHistory);

            %% NoInputs
            results = strrep(results, "<<NoInputs>>", string(numInputs));

            %% NoOutputs
            results = strrep(results, "<<NoOutputs>>", string(numOutputs));

            %% NoParams
            results = strrep(results, "<<NoParams>>", string(numParameters));

            %% Int states needed
            numIntStates = heapSize(modelDescriptions); % What value does this need to be?
            results = strrep(results, "<<NumIntStatesNeeded>>", string(numIntStates));

            %% SampleTime
            results = strrep(results, "<<SampleTime>>", string(modelDescriptions.SampleTime));

            % Set number of tasks
            results = strrep(results, "<<Number of tasks>>", string(modelDescriptions.NumberOfTasks));

            %% RTM Struct
            results = strrep(results, "<<RTMStruct>>", modelDescriptions.RTMStructName);
            results = strrep(results, "<<RTMType>>", modelDescriptions.RTMVarType);

            %% Model name
            results = strrep(results, "<<ModelName>>", model);
            results = strrep(results, "<<WrapperName>>", cigreInterface);

            %% Write the results
            filename = nvp.DLLName + ".h";
            
        end
    end
end

function heap = heapSize(modelDescriptions)

heap = "sizeof(<<RTMType>>)";

intStates = [modelDescriptions.InternalData, modelDescriptions.InputData modelDescriptions.OutputData];
for i = 1:numel(intStates)
    intState = intStates(i);
    type = intState.Type;
    heap = heap + " + sizeof("+type+")";
end

if isempty(heap) || ismissing(heap)
    heap = 80000; % Make sure there is some heap...
    warning("Heap calculation failed")
end
end

