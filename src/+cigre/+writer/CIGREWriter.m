classdef CIGREWriter
% Generates the CIGRE wrapper .c and .h source files from a ModelDescription.
% Each public method loads a template and applies a pipeline of named
% substitution steps, with all logic delegated to private static helpers.

    methods (Static)

        function [results, filename] = writeDLL(modelDescriptions, nvp)
            arguments
                modelDescriptions (1,1) cigre.description.ModelDescription
                nvp.DLLName (1,1) string = modelDescriptions.ModelName + "_CIGRE"
                nvp.ParameterConfig (1,1) cigre.config.ParameterConfiguration = ...
                    cigre.config.ParameterConfiguration()
            end

            results = readFromFile("TemplateWrapper.c");
            results = cigre.writer.CIGREWriter.applyInitializeOnly(results, modelDescriptions);
            results = cigre.writer.CIGREWriter.applyHeapAndMemoryDeclarations(results, modelDescriptions);
            results = cigre.writer.CIGREWriter.applyInternalStateMapping(results, modelDescriptions);
            results = cigre.writer.CIGREWriter.applyParameterMappings(results, modelDescriptions, nvp.ParameterConfig);
            results = cigre.writer.CIGREWriter.applyStateBackupRestore(results, modelDescriptions.RTMStruct);
            results = cigre.writer.CIGREWriter.applyIOUnpacking(results, modelDescriptions);
            results = cigre.writer.CIGREWriter.applyFunctionSignatures(results, modelDescriptions);

            % Substitute model/wrapper names last so that all previously
            % generated code fragments containing these tags are also resolved
            results = strrep(results, "<<RTMStructName>>", modelDescriptions.RTMStructName);
            results = strrep(results, "<<RTMType>>",       modelDescriptions.RTMVarType);
            results = strrep(results, "<<ModelName>>",     modelDescriptions.ModelName);
            results = strrep(results, "<<WrapperName>>",   modelDescriptions.CIGREInterfaceName);

            filename = nvp.DLLName + ".c";
        end

        function [results, filename] = writeHeader(modelDescriptions, nvp)
            arguments
                modelDescriptions (1,1) cigre.description.ModelDescription
                nvp.DLLName (1,1) string = modelDescriptions.ModelName + "_CIGRE"
                nvp.ParameterConfig (1,1) cigre.config.ParameterConfiguration = ...
                    cigre.config.ParameterConfiguration()
            end

            cigreInterface = modelDescriptions.CIGREInterfaceName;

            % Partition parameters up front so counts and definitions are consistent
            allParams = modelDescriptions.CIGREParameters;
            [visibleParams, ~] = nvp.ParameterConfig.partitionParameters(allParams);

            results = readFromFile("TemplateWrapper.h");
            results = cigre.writer.CIGREWriter.applyHeaderIncludes(results, modelDescriptions);
            results = cigre.writer.CIGREWriter.applyInputSection(results, modelDescriptions, cigreInterface);
            results = cigre.writer.CIGREWriter.applyOutputSection(results, modelDescriptions, cigreInterface);
            results = cigre.writer.CIGREWriter.applyParameterSection(results, visibleParams, cigreInterface);
            results = cigre.writer.CIGREWriter.applyGetSetMethodDeclarations(results, modelDescriptions.Parameters);
            results = cigre.writer.CIGREWriter.applyModelInfoStruct(results, modelDescriptions, numel(visibleParams));

            filename = nvp.DLLName + ".h";
        end

    end

    methods (Static, Access = private)

        % --- writeDLL helpers ---

        function results = applyInitializeOnly(results, desc)
            % Substitute the initialize-only code block, or a placeholder comment
            % if the model has no initialize-only section.
            code = desc.InitializeOnlyCode;
            if code == ""
                code = "// No initialize code required";
            end
            results = strrep(results, "<<InitializeOnly>>", code);
            results = strrep(results, "<<CigreHeader>>", desc.ModelName + "_CIGRE.h");
        end

        function results = applyHeapAndMemoryDeclarations(results, desc)
            % Substitute the heap size expression, the RTM struct declaration,
            % and generate heap_malloc / heap_get_address calls for each internal
            % state, input, and output variable.
            results = strrep(results, "<<heap definition>>", heapSize(desc));
            results = strrep(results, "<<RTMVarType>>", desc.RTMVarType);
            results = strrep(results, "<<RTMStructName>>", desc.RTMStructName);

            idx = 1;
            for i = 1:numel(desc.InternalData)
                [results, idx] = insertMemoryEntry( ...
                    results, desc.InternalData(i), desc.InternalData(i).ERTName, idx);
            end

            ioStates = [desc.InputData, desc.OutputData];
            for i = 1:numel(ioStates)
                [results, idx] = insertMemoryEntry( ...
                    results, ioStates(i), ioStates(i).ERTName, idx);
            end

            % Clear sentinels left by the incremental insertion pattern
            results = strrep(results, "<<InternalStatesMalloc>>", "");
            results = strrep(results, "<<InternalStatesRestore>>", "");
        end

        function results = applyInternalStateMapping(results, desc)
            % Wire the heap-allocated state pointers into the RTM struct fields
            % and initialise the local error status string.
            mapping = ...
                "char errorStatus[255];" + newline ...
                + "    errorStatus[0] = '\0';" + newline ...
                + "    <<RTMStructName>>->errorStatus = errorStatus;" + newline;

            for i = 1:numel(desc.RTMStruct)
                name = desc.RTMStruct(i).ERTName;
                mapping = mapping + newline ...
                    + "    <<RTMStructName>>->" + name + " = " + name + ";" + newline;
            end

            results = strrep(results, "<<MapInternalStatesToModel>>", mapping);
        end

        function results = applyParameterMappings(results, desc, paramConfig)
            % Generate C code that writes CIGRE parameter struct values into the
            % model's internal parameter storage. Visible parameters are read from
            % the instance; hidden parameters are hardcoded as literal defaults.
            [visibleParams, hiddenParams] = paramConfig.partitionParameters(desc.CIGREParameters);
            paramMaps = buildModelArgMappings(visibleParams, hiddenParams);
            paramMaps = paramMaps + buildGlobalParamMappings(visibleParams, hiddenParams);
            results = strrep(results, "<<MapParamsToModel>>", paramMaps);
        end

        function results = applyStateBackupRestore(results, rtmStructs)
            % Generate malloc/free-based backup and restore code for RTM structs,
            % used in Model_FirstCall to preserve state across snapshot reinitialisation.
            backupCode  = "";
            restoreCode = "";

            for i = 1:numel(rtmStructs)
                rtmType = rtmStructs(i).Type;
                rtmName = rtmStructs(i).ERTName;

                backupCode = backupCode ...
                    + newline + "    " + rtmType + "* " + rtmName + "_backup;" ...
                    + newline + "    " + rtmName + "_backup = malloc(sizeof(" + rtmType + "));" ...
                    + newline + "    *" + rtmName + "_backup = *" + rtmName + ";";

                restoreCode = restoreCode ...
                    + newline + "    *" + rtmName + " = *" + rtmName + "_backup;" ...
                    + newline + "    free(" + rtmName + "_backup);";
            end

            results = strrep(results, "<<InternalStatesCache>>",           backupCode);
            results = strrep(results, "<<InternalStatesRestoreFromCache>>", restoreCode);
        end

        function results = applyIOUnpacking(results, desc)
            % Generate casts from the instance void pointers to typed model structs,
            % and the copy statements that move data between instance and model.
            inputType = string([desc.InputData.Type]);
            inputName = string([desc.InputData.ERTName]);
            if isempty(inputType)
                results = strrep(results, "<<InputUnpack>>",    " // No inputs");
                results = strrep(results, "<<ApplyInputData>>", " // No input data");
            else
                results = strrep(results, "<<InputUnpack>>", ...
                    "<<InputType>>* inputs = (<<InputType>>*)instance->ExternalInputs;");
                results = strrep(results, "<<InputType>>",      inputType);
                results = strrep(results, "<<ApplyInputData>>", "*<<InputName>> = *inputs;");
                results = strrep(results, "<<InputName>>",      inputName);
            end

            outputType = string([desc.OutputData.Type]);
            outputName = string([desc.OutputData.ERTName]);
            if isempty(outputType)
                results = strrep(results, "<<OutputUnpack>>",    " // No outputs");
                results = strrep(results, "<<ApplyOutputData>>", " // No output data");
            else
                results = strrep(results, "<<OutputUnpack>>", ...
                    "<<OutputType>>* outputs = (<<OutputType>>*)instance->ExternalOutputs;");
                results = strrep(results, "<<OutputType>>",       outputType);
                results = strrep(results, "<<ApplyOutputData>>",  "*outputs = *<<OutputName>>;");
                results = strrep(results, "<<OutputName>>",       outputName);
            end

            if desc.NumCigreParameters == 0
                results = strrep(results, "<<ParamUnpack>>", " // No parameters");
            else
                results = strrep(results, "<<ParamUnpack>>", ...
                    "MyModelParameters* parameters = (MyModelParameters*)instance->Parameters;");
            end
        end

        function results = applyFunctionSignatures(results, desc)
            % Substitute the generated model initialize and step function names
            % and their argument lists.
            initInputs = strjoin( ...
                string({desc.InitialiseInputs.ERTName}), ", ");
            results = strrep(results, "<<ModelInitialize>>",      desc.InitializeName);
            results = strrep(results, "<<ModelInitialiseInputs>>", initInputs);

            stepInputs = strjoin( ...
                string({desc.StepInputs.ERTName}), ", ");
            results = strrep(results, "<<ModelStep>>",       desc.StepName);
            results = strrep(results, "<<ModelStepInputs>>", stepInputs);
        end

        % --- writeHeader helpers ---

        function results = applyHeaderIncludes(results, desc)
            arguments
                results (1,:) string
                desc (1,1) cigre.description.ModelDescription
            end
            % Substitute the model wrapper header include and the optional
            % model_reference_types.h include required by some model configurations.
            results = strrep(results, "<<WrapperHeader>>", desc.CIGREInterfaceName + ".h");
            
            here = desc.CodeGenFolder;
            if isfile(fullfile(here, "/slprj/cigre/_sharedutils/model_reference_types.h"))
                modelRefHeader = "#include ""model_reference_types.h""";
            else
                modelRefHeader = "";
            end
            results = strrep(results, "<<model_reference_types>>", modelRefHeader);
        end

        function results = applyInputSection(results, desc, cigreInterface)
            % Substitute the #define count, the struct field declarations,
            % and the InputSignals array for all model inputs.
            simulinkNames = string([desc.Inputs.SimulinkName]');
            cigreNames  = string([desc.Inputs.CIGREName]');
            types = util.TranslateTypes.translateType( ...
                [desc.Inputs.Type]', "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';
            dims  = cellfun(@(x) string(prod(x)), {desc.Inputs.Dimensions})';

            % ERTName is already a valid C identifier (from extractExternalName).
            % Use it directly for struct field declarations; SimulinkName (the
            % human-readable Simulink port name) is used for the string-literal
            % .Name / .Description fields in the InputSignals array.
            results = strrep(results, "<<NumInputs>>",  string(numel(simulinkNames)));
            results = strrep(results, "<<DefineInputs>>", ...
                strjoin(types + " " + cigreNames + "[" + dims + "];", newline));

            template = strjoin([ ...
                "[<<Num>>] = {", ...
                "           .Name = ""<<Name>>"",                                  // Signal name", ...
                "           .Description = ""<<Description>>"",                    // Simulink port name", ...
                "           .Unit = ""pu"",                                        // Units", ...
                "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<Type>>, // Signal type", ...
                "           .Width = <<Width>>                                     // Signal dimension", ...
                "     }"], newline);

            results = strrep(results, "<<InputDefinition>>", ...
                buildSignalDefinitions(cigreNames, simulinkNames, types, dims, template));
        end

        function results = applyOutputSection(results, desc, cigreInterface)
            % Substitute the #define count, the struct field declarations,
            % and the OutputSignals array for all model outputs.
            simulinkNames = string([desc.Outputs.SimulinkName]');
            cigreNames = string([desc.Outputs.CIGREName]');
            types = util.TranslateTypes.translateType( ...
                [desc.Outputs.Type]', "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';
            dims  = cellfun(@(x) string(prod(x)), {desc.Outputs.Dimensions})';

            % ERTName is already a valid C identifier — see applyInputSection.
            results = strrep(results, "<<NumOutputs>>",  string(numel(simulinkNames)));
            results = strrep(results, "<<DefineOutputs>>", ...
                strjoin(types + " " + cigreNames + "[" + dims + "];", newline));

            template = strjoin([ ...
                "[<<Num>>] = {", ...
                "           .Name = ""<<Name>>"",                                  // Signal name", ...
                "           .Description = ""<<Description>>"",                    // Simulink port name", ...
                "           .Unit = ""pu"",                                        // Units", ...
                "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<Type>>, // Signal type", ...
                "           .Width = <<Width>>                                     // Signal dimension", ...
                "      }"], newline);

            results = strrep(results, "<<OutputDefinition>>", ...
                buildSignalDefinitions(cigreNames, simulinkNames, types, dims, template));
        end

        function results = applyParameterSection(results, visibleParams, cigreInterface)
            % Substitute the #define count, the struct field declarations,
            % and the Parameters array for all visible model parameters.
            nParams = numel(visibleParams);
            results = strrep(results, "<<NumParam>>", string(nParams));

            if nParams == 0
                results = strrep(results, "<<DefineParameters>>",    "");
                results = strrep(results, "<<ParameterDefinitions>>", "");
                return
            end

            cigreParamNames = string([visibleParams.CIGREName]');
            cigreParamTypes = util.TranslateTypes.translateType( ...
                [visibleParams.Type]', "From", "Simulink", "To", "CIGRE", "Model", cigreInterface)';

            results = strrep(results, "<<DefineParameters>>", ...
                strjoin(cigreParamTypes + " " + cigreParamNames + ";", newline));

            results = strrep(results, "<<ParameterDefinitions>>", ...
                buildParameterDefinitions(visibleParams, cigreParamTypes));
        end

        function results = applyGetSetMethodDeclarations(results, parameters)
            % Generate forward declarations for any GetSet parameter methods,
            % which have implementations provided outside the generated code.
            getSetParams = parameters(string([parameters.StorageSpecifier]) == "GetSet");
            for i = 1:numel(getSetParams)
                decl = "void " + getSetParams(i).GetMethod + "();" + newline ...
                    + "<<ParamGetMethods>>";
                results = strrep(results, "<<ParamGetMethods>>", decl);
            end
            results = strrep(results, "<<ParamGetMethods>>", "");
        end

        function results = applyModelInfoStruct(results, desc, numVisibleParams)
            % Substitute all fields of the Model_Info struct: metadata strings,
            % signal counts, sample time, and the integer state heap size.
            results = strrep(results, "<<ModelName>>",           desc.ModelName);
            results = strrep(results, "<<ModelVersion>>",        desc.ModelVersion);
            results = strrep(results, "<<Description>>",         desc.Description);
            results = strrep(results, "<<ModelCreatedDate>>",    desc.CreatedOn);
            results = strrep(results, "<<ModelCreatedBy>>",      desc.CreatedBy);
            results = strrep(results, "<<ModelModifiedOn>>",     desc.ModifiedOn);
            results = strrep(results, "<<ModelModifiedBy>>",     desc.ModifiedBy);
            results = strrep(results, "<<ModelModifiedComment>>", desc.ModelModifiedComment);
            results = strrep(results, "<<ModelHistory>>",        desc.ModelModifiedHistory);
            results = strrep(results, "<<SampleTime>>",          sprintf('%.17e', desc.SampleTime));

            % <<NoX>> tags appear in the Model_Info struct; <<NumX>> tags appear
            % in the #define macros above - they hold the same values
            results = strrep(results, "<<NoInputs>>",  string(numel(desc.Inputs)));
            results = strrep(results, "<<NoOutputs>>", string(numel(desc.Outputs)));
            results = strrep(results, "<<NoParams>>",  string(numVisibleParams));

            % heapSize returns an expression containing <<RTMType>>, which is
            % resolved in the final strrep below after the expression is embedded
            results = strrep(results, "<<NumIntStatesNeeded>>", string(heapSize(desc)));
            results = strrep(results, "<<RTMType>>",            desc.RTMVarType);
        end

    end
end


% --- Local helper functions (not class methods) ---

function [results, nextIdx] = insertMemoryEntry(results, state, varName, idx)
% Append one heap_malloc / heap_get_address line to the accumulating
% placeholder lists, using incremental strrep to build up the list.
% The (void) cast after each declaration suppresses MSVC C4189 for variables
% that are allocated to reserve heap space but not directly dereferenced.
type = state.Type;
ptrs = state.Pointers;

mallocLine  = type + ptrs + " " + varName ...
    + " = heap_malloc(&instance->IntStates[0], (int32_t)sizeof(" + type + "));" ...
    + newline + "    (void)" + varName + ";" ...
    + newline + "    <<InternalStatesMalloc>>";

restoreLine = type + ptrs + " " + varName ...
    + " = (" + type + ptrs + ")heap_get_address(&instance->IntStates[0], " + idx + ");" ...
    + newline + "    (void)" + varName + ";" ...
    + newline + "    <<InternalStatesRestore>>";

results  = strrep(results, "<<InternalStatesMalloc>>", mallocLine);
results  = strrep(results, "<<InternalStatesRestore>>", restoreLine);
nextIdx  = idx + 1;
end


function defs = buildSignalDefinitions(cigreNames, simulinkNames, types, dims, template)
% Build a comma-separated list of CIGRE signal definition structs.

defs = strings(numel(cigreNames), 1);
for i = 1:numel(cigreNames)
    entry = template;
    entry = strrep(entry, "<<Num>>",         string(i-1));
    entry = strrep(entry, "<<Name>>",        cigreNames(i));
    entry = strrep(entry, "<<Description>>", simulinkNames(i));
    entry = strrep(entry, "<<Type>>",        types(i));
    entry = strrep(entry, "<<Width>>",       dims(i));
    defs(i) = entry;
end
defs = strjoin(defs, "," + newline);
end


function paramDef = buildParameterDefinitions(visibleParams, cigreParamTypes)
% Build the array of IEEE_Cigre_DLLInterface_Parameter structs describing
% each visible parameter's name, type, and default/min/max values.
template = strjoin([ ...
    "[<<Num>>] = {", ...
    "           .Name = ""<<Name>>"",                                  // Parameter name", ...
    "           .Description = ""<<Description>>"",                    // Simulink parameter name", ...
    "           .Unit = ""sec"",                                       // Units", ...
    "           .DataType = IEEE_Cigre_DLLInterface_DataType_<<Type>>, // Parameter type", ...
    "           .FixedValue = 0,                                       // 0 = modifiable, 1 = fixed at T0", ...
    "           .DefaultValue.<<ValType>> = <<Default>>,               // Default value", ...
    "           .MinValue.<<ValType>> = <<Min>>,                       // Minimum value", ...
    "           .MaxValue.<<ValType>> = <<Max>>                        // Maximum value", ...
    "      }"], newline);

paramDef = strings(numel(visibleParams), 1);
for i = 1:numel(visibleParams)
    p = visibleParams(i);

    % Derive the union field name from the CIGRE type, e.g. real64_T -> Real64_Val
    valType = strrep(cigreParamTypes(i), "_T", "_Val");
    valType = replaceBetween(valType, 1, 1, upper(extract(valType, 1)));

    entry = template;
    entry = strrep(entry, "<<Num>>",         string(i-1));
    entry = strrep(entry, "<<Name>>",        p.CIGREName);
    entry = strrep(entry, "<<Description>>", p.SimulinkName);
    entry = strrep(entry, "<<Type>>",        cigreParamTypes(i));
    entry = strrep(entry, "<<ValType>>",     valType);
    entry = strrep(entry, "<<Default>>",     formatCNumericLiteral(double(p.DefaultValue)));
    entry = strrep(entry, "<<Min>>",         formatCNumericLiteral(double(p.Min)));
    entry = strrep(entry, "<<Max>>",         formatCNumericLiteral(double(p.Max)));
    paramDef(i) = entry;
end
paramDef = strjoin(paramDef, "," + newline);
end



function literal = formatCNumericLiteral(value)
% Format a numeric value as a safe C literal.
% Integer minimum values (e.g. -2147483648 for int32) cannot be written
% as a negative literal in C because the positive part overflows the signed
% type before the unary minus is applied, causing MSVC warning C4146.
% The safe form expresses them as (-MAX - 1).
intMinMap = [ ...
    double(intmin('int8')),  "(-127 - 1)"; ...
    double(intmin('int16')), "(-32767 - 1)"; ...
    double(intmin('int32')), "(-2147483647 - 1)"; ...
];

for i = 1:size(intMinMap, 1)
    if value == double(intMinMap(i,1))
        literal = intMinMap(i, 2);
        return
    end
end

literal = string(value);
end


function paramMaps = buildModelArgMappings(visibleParams, hiddenParams)
% Generate C assignments for model-argument parameters. Visible ones read
% from the CIGRE parameters struct; hidden ones use hardcoded literal defaults
% to exclude them from the DLL interface without changing model behaviour.
modelArgVisible = visibleParams([visibleParams.IsModelArgument]);
modelArgHidden  = hiddenParams([hiddenParams.IsModelArgument]);

paramMaps = "";
for i = 1:numel(modelArgVisible)
    p = modelArgVisible(i);
    structName = erase(p.StorageSpecifier, "ModelArgument:");
    paramMaps = paramMaps ...
        + "<<RTMStructName>>->dwork->mdl_InstanceData.rtm." + structName + "->" ...
        + p.SimulinkName + " = parameters->" + p.CIGREName + ";" + newline;
end

for i = 1:numel(modelArgHidden)
    p = modelArgHidden(i);
    structName = erase(p.StorageSpecifier, "ModelArgument:");
    paramMaps = paramMaps ...
        + "<<RTMStructName>>->dwork->mdl_InstanceData.rtm." + structName + "->" ...
        + p.SimulinkName + " = " + string(double(p.DefaultValue)) + ";" + newline;
end

if isempty(modelArgVisible) && isempty(modelArgHidden)
    paramMaps = "// No model argument parameters found" + newline;
end
end


function paramMaps = buildGlobalParamMappings(visibleParams, hiddenParams)
% Generate C assignments for global (non-model-argument) parameters.
% Global parameters are warned about because they are shared across instances,
% creating a risk of non-determinism when the DLL is called in parallel.
globalVisible = visibleParams(~[visibleParams.IsModelArgument]);
globalHidden  = hiddenParams(~[hiddenParams.IsModelArgument]);

if ~isempty(globalVisible) || ~isempty(globalHidden)
    warning("CIGRE:CIGREWriter:GlobalParameters", ...
        "Global parameters found: %s. DLL may be non-deterministic when called in parallel.", ...
        strjoin([string([globalVisible.SimulinkName]), string([globalHidden.SimulinkName])], ", "));
    paramMaps = newline + "// Globally defined parameters - these may break parallel execution" + newline;
else
    paramMaps = "";
end


for i = 1:numel(globalVisible)
    p = globalVisible(i);
    paramMaps = paramMaps + p.ERTName + " = parameters->" + p.CIGREName + ";" + newline;
end
for i = 1:numel(globalHidden)
    p = globalHidden(i);
    paramMaps = paramMaps + p.ERTName + " = " + string(double(p.DefaultValue)) + ";" + newline;
end
end


function heap = heapSize(modelDescriptions)
% Compute a C sizeof() expression summing all state variable types,
% so the CIGRE runtime can allocate the correct heap at initialisation.
% <<RTMType>> is left unresolved here and substituted by the caller.
heap = "sizeof(<<RTMType>>)";

allStates = [modelDescriptions.InternalData, ...
    modelDescriptions.InputData, ...
    modelDescriptions.OutputData];

for i = 1:numel(allStates)
    type = allStates(i).Type;
    heap = heap + " + sizeof(" + type + ")";
end

end