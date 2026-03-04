classdef tModelDescription < matlab.mock.TestCase

    properties (TestParameter)
        ModelName = {"Test_MultiInput", "Test_MultiOutput", "Test_MIMO", "Test_ParamModel", "Test_FastRef", "Snap"}
    end

    properties
        ModelHandle
    end

    methods(Test)
        % Test methods

        function processRateSchedulerCodeMultiLineCall(testCase)

            demoCode = ...
                ["static void rate_scheduler(RealTimeModel_T *"
                "const RealTimeModel_M);"
                ""
                "/*"
                "*   This function updates active task flag for each subrate."
                "* The function is called at model base rate, hence the"
                "* generated code self-manages all its subrates."
                "*/"
                "static void rate_scheduler(RealTimeModel_T *"
                "  const RealTimeModel_M)"
                "{"
                "/* Compute which subrates run during the next base time step.  Subrates"
                "   * are an integer multiple of the base rate counter.  Therefore, the subtask"
                "   * counter is reset when it reaches its limit (zero means run)."
                "   */"
                "  (RealTimeModel_M->Timing.TaskCounters.TID[1])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[1]) > 49)"
                "{                                    /* Sample time: [0.005s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[1] = 0;"
                "  }"
                "}"];
            demoCode = strjoin(demoCode, newline);

            wrapperName = "RealTimeModel";
            tbc = cigre.description.ModelDescription.processRateSchedulerCode(demoCode, wrapperName);
            tbc = strsplit(tbc, newline)';

            expected = [...
                "static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)"
                "{"
                "/* Compute which subrates run during the next base time step.  Subrates"
                "   * are an integer multiple of the base rate counter.  Therefore, the subtask"
                "   * counter is reset when it reaches its limit (zero means run)."
                "   */"
                "  (RealTimeModel_M->Timing.TaskCounters.TID[1])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[1]) > 49)"
                "{                                    /* Sample time: [0.005s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[1] = 0;"
                "  }"
                "}"];

            testCase.verifyEqual(tbc, expected);
        end

        function processRateSchedulerCodeMultiRates(testCase)

            demoCode = ...
                ["static void rate_scheduler(RealTimeModel_T *const RealTimeModel_M);"
                ""
                "/*"
                " *         This function updates active task flag for each subrate."
                " *         The function is called at model base rate, hence the"
                " *         generated code self-manages all its subrates."
                " */"
                "static void rate_scheduler(RealTimeModel_T *const RealTimeModel_M)"
                "{"
                "  /* Compute which subrates run during the next base time step.  Subrates"
                "   * are an integer multiple of the base rate counter.  Therefore, the subtask"
                "   * counter is reset when it reaches its limit (zero means run)."
                "   */"
                "  (RealTimeModel_M->Timing.TaskCounters.TID[1])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[1]) > 4) {/* Sample time: [0.5s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[1] = 0;"
                "  }"

                "  (RealTimeModel_M->Timing.TaskCounters.TID[2])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[2]) > 9) {/* Sample time: [1.0s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[2] = 0;"
                "  }"
                "}"];

            demoCode = strjoin(demoCode, newline);

            wrapperName = "RealTimeModel";
            tbc = cigre.description.ModelDescription.processRateSchedulerCode(demoCode, wrapperName);
            tbc = strsplit(tbc, newline)';

            expected = [...
                "static void rate_scheduler(<<RTMStruct>> *const RealTimeModel_M)"
                "{"
                "  /* Compute which subrates run during the next base time step.  Subrates"
                "   * are an integer multiple of the base rate counter.  Therefore, the subtask"
                "   * counter is reset when it reaches its limit (zero means run)."
                "   */"
                "  (RealTimeModel_M->Timing.TaskCounters.TID[1])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[1]) > 4) {/* Sample time: [0.5s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[1] = 0;"
                "  }"

                "  (RealTimeModel_M->Timing.TaskCounters.TID[2])++;"
                "  if ((RealTimeModel_M->Timing.TaskCounters.TID[2]) > 9) {/* Sample time: [1.0s, 0.0s] */"
                "    RealTimeModel_M->Timing.TaskCounters.TID[2] = 0;"
                "  }"
                "}"];

            testCase.verifyEqual(tbc, expected);
        end

        function processTimingBridgeWithJunk(testCase)

            demoCode = ...
                ["typedef struct tag_RealTimeModel_T {"
                "  const char_T *errorStatus;"
                "  rtTimingBridge timingBridge"
                "  B_ModelName_wrapper_T *blockIO;"
                "  "
                "  /*"
                "   * comments"
                "   */"
                "  struct {"
                "    struct {"
                "      uint32_T TID[2];"
                "    } TaskCounters;"
                "  } Timing;"
                "} RealTimeModel_T;"];

            demoCode = strjoin(demoCode, newline);

            tbc = cigre.description.ModelDescription.processRTMStructCode(demoCode);
            tbc = strsplit(tbc, newline)';
            expected = ...
                ["typedef struct tag_RealTimeModel_T {"
                "  const char_T *errorStatus;"
                "  rtTimingBridge timingBridge;"
                "  /*"
                "   * Timing:"
                "   * The following substructure contains information regarding"
                "   * the timing information for the model."
                "   */"
                "  struct {"
                "    struct {"
                "      uint32_T TID[2];"
                "    } TaskCounters;"
                "  } Timing;"
                "}<<RTMStruct>>;"];

            testCase.verifyEqual(tbc, expected);
        end



        % --- processRTMStructCode -----------------------------------------

        function singleRateModelProducesNoTimingBridge(testCase)
            % A single-rate model struct has no TID array and no rtTimingBridge,
            % so no timing bridge declarations should appear in the output.
            header = [
                "typedef struct tag_RTM_M_T {"
                "  const char_T *errorStatus;"
                "} RT_MODEL_M_T;"
                ]';
            [tbc, nTasks] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyFalse(contains(tbc, "timingBridge"), ...
                "Single-rate model must not include timingBridge declaration");
            testCase.verifyEqual(nTasks, 1);
        end

        function multiRateModelExtractsTimingBridgeAndTaskCount(testCase)
            % A multi-rate struct includes rtTimingBridge and TID[n]; both must
            % be captured so the generated DLL can manage task scheduling.
            header = [
                "typedef struct tag_RTM_M_T {"
                "  const char_T *errorStatus;"
                "  rtTimingBridge timingBridge;"
                "  struct {"
                "    struct {"
                "      uint32_T TID[3];"
                "    } TaskCounters;"
                "  } Timing;"
                "} RT_MODEL_M_T;"
                ]';
            [tbc, nTasks] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyEqual(nTasks, 3);
            testCase.verifyTrue(contains(tbc, "timingBridge"), ...
                "Multi-rate model must include timingBridge declaration");
        end

        function processRTMStructCodeInsertsRTMStructPlaceholder(testCase)
            % The closing typedef brace must be replaced with <<RTMStruct>> so the
            % writer can inject the correct variable name at code generation time.
            header = [
                "typedef struct tag_RTM_T {"
                "  const char_T *errorStatus;"
                "} RT_MODEL_T;"
                ]';
            [tbc, ~] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyTrue(contains(tbc, "<<RTMStruct>>"), ...
                "Closing typedef line must contain the <<RTMStruct>> placeholder");
        end

        function processRTMStructCodeWithNoStructReturnsEmptyAndScalarTaskCount(testCase)
            % When no struct tag_... pattern exists the timing bridge is empty
            % and task count is the scalar double 1 (single-rate default).
            header = "/* no struct tag here */";
            [tbc, nTasks] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyEqual(tbc, "");
            testCase.verifyEqual(nTasks, 1);
        end

        function processRTMStructCodeAcceptsScalarNewlineJoinedInput(testCase)
            % The method must accept a single newline-joined string as well as a
            % string array, since both forms occur during the build pipeline.
            header = strjoin([
                "typedef struct tag_RTM_T {"
                "  const char_T *errorStatus;"
                "} RT_MODEL_T;"
                ], newline);
            [tbc, nTasks] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyClass(tbc, 'string');
            testCase.verifyEqual(nTasks, 1);
        end

        function processRTMStructCodeIncludesErrorStatusWhenPresent(testCase)
            header = [
                "typedef struct tag_RTM_T {"
                "  const char_T *errorStatus;"
                "} RT_MODEL_T;"
                ]';
            [tbc, ~] = cigre.description.ModelDescription.processRTMStructCode(header);
            testCase.verifyTrue(contains(tbc, "errorStatus"), ...
                "errorStatus field must be preserved so the DLL can report errors");
        end

        % --- processInitializeCode ----------------------------------------

        function processInitializeCodeRenamesFunctionWithOnlySuffix(testCase)
            % The extracted function must carry the _only suffix so it can be called
            % independently of the RTM struct allocation in the main initialise path.
            source = [
                "/* Model initialize function */"
                "void MyModel_initialize(real_T *rtM)"
                "{"
                "  rtM->errorStatus = 0;"
                "};"
                ]';
            code = cigre.description.ModelDescription.processInitializeCode(source);
            testCase.verifyTrue(contains(code, "_initialize_only"), ...
                "Extracted function must be renamed to the _only variant");
        end

        function processInitializeCodeProducesFallbackWhenAbsent(testCase)
            % When no initialize function exists a minimal body must still be
            % returned so the writer always has something to substitute.
            source = "/* unrelated code only */";
            code = cigre.description.ModelDescription.processInitializeCode(source);
            testCase.verifyNotEmpty(code);
            testCase.verifyTrue(contains(code, "};"), ...
                "Fallback must produce a valid block ending with };");
        end

        function processInitializeCodeExtractsDefinitionNotDeclaration(testCase)
            % The first occurrence of the initialize comment marks the forward
            % declaration; the second marks the definition. Only the definition
            % body should be extracted to avoid a duplicated signature.
            source = [
                "/* Model initialize function */"
                "void MyModel_initialize(real_T *rtM);"
                ""
                "/* Model initialize function */"
                "void MyModel_initialize(real_T *rtM)"
                "{"
                "  rtM->errorStatus = 0;"
                "};"
                ]';
            code = cigre.description.ModelDescription.processInitializeCode(source);
            occurrences = numel(strfind(code, "_initialize_only"));
            testCase.verifyEqual(occurrences, 1, ...
                "Only the definition should be renamed — not the declaration");
        end

        function processInitializeCodeAcceptsScalarNewlineJoinedInput(testCase)
            source = strjoin([
                "/* Model initialize function */"
                "void M_initialize(real_T *x)"
                "{"
                "};"
                ], newline);
            code = cigre.description.ModelDescription.processInitializeCode(source);
            testCase.verifyTrue(contains(code, "_initialize_only"));
        end

        % --- analyse via mock CodeDescriptor ------------------------------

        function constructorDoesNotRequireSimulink(testCase)
            % Passing explicit folder paths must bypass the Simulink.fileGenControl
            % defaults so the constructor is usable without a Simulink licence.
            testCase.verifyWarningFree(...
                @() cigre.description.ModelDescription("TestModel", ...
                "CIGREInterfaceName", "TestWrapper", ...
                "CodeGenFolder", tempdir(), ...
                "WorkFolder", tempdir()));
        end

        function analysePopulatesAllMetadataFields(testCase)
            % analyse must copy every ModelMetadata field into the corresponding
            % ModelDescription property so callers see a fully populated description.
            metadata = cigre.description.ModelMetadata(...
                "ModelVersion", "2.0.1", ...
                "Description", "Test DLL", ...
                "ModifiedBy", "alice", ...
                "CreatedBy", "bob", ...
                "SampleTime", "1.234e-03", ...
                "ModifiedOn", "2024-01-01");
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior, "Metadata", metadata);

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyEqual(desc.ModelVersion, "2.0.1");
            testCase.verifyEqual(desc.Description, "Test DLL");
            testCase.verifyEqual(desc.ModifiedBy, "alice");
            testCase.verifyEqual(desc.CreatedBy, "bob");
            testCase.verifyEqual(desc.SampleTime, "1.234e-03");
            testCase.verifyEqual(desc.ModifiedOn, "2024-01-01");
        end

        function analysePopulatesInitialiseAndStepAndTerminateNames(testCase)
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior, ...
                "InitName", "MyModel_initialize", ...
                "StepName", "MyModel_step", ...
                "TerminateName", "MyModel_terminate");

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyEqual(desc.InitializeName, "MyModel_initialize");
            testCase.verifyEqual(desc.StepName, "MyModel_step");
            testCase.verifyEqual(desc.TerminateName, "MyModel_terminate");
        end

        function analyseWithEmptyFunctionInterfacesLeavesNamesEmpty(testCase)
            % When none of the four entry points are present (e.g. a minimal
            % model) all function names must remain "" and no error is thrown.
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior);

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyEqual(desc.InitializeName, "");
            testCase.verifyEqual(desc.StepName, "");
            testCase.verifyEqual(desc.TerminateName, "");
            testCase.verifyEqual(desc.ModelRefInitialiseName, "");
        end

        function analysePopulatesInputsAndOutputsFromDescriptor(testCase)
            inputs = cigre.description.Variable.create(...
                "SimulinkName", ["In1", "In2"], ...
                "ExternalName", ["In1", "In2"], ...
                "Type", ["real_T", "real_T"], ...
                "Pointers", ["*", "*"]);
            outputs = cigre.description.Variable.create(...
                "SimulinkName", "Out1", ...
                "ExternalName", "Out1", ...
                "Type", "real_T", ...
                "Pointers", "*");
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior, "Inputs", inputs, "Outputs", outputs);

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyNumElements(desc.Inputs, 2);
            testCase.verifyNumElements(desc.Outputs, 1);
        end

        function analyseExtractsRTMStructFromInternalData(testCase)
            % The variable ending in _M must be separated from InternalData and
            % stored in RTMVarType and RTMStruct to drive the state-memory layout.
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior);

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyEqual(desc.RTMVarType, "RT_MODEL_MyModel_T", ...
                "RTMVarType must be set from the _M variable type");
            testCase.verifyNumElements(desc.InternalData, 1, ...
                "The _M variable must be removed from InternalData after extraction");
        end

        function analysePopulatesStepInputVariables(testCase)
            % Step inputs are assembled from the function interface arguments;
            % verifying them end-to-end confirms processInterface is exercised.
            rtmType = "RT_MODEL_MyModel_T";
            stepIface = cigre.description.FunctionInterface(...
                "Name", "MyModel_step", ...
                "ArgumentNames", ["MyModel_M", "localDW"], ...
                "ArgumentTypes", [rtmType, "DW_MyModel_T"], ...
                "ArgumentPointers", ["*", "*"]);
            [mock, behavior] = testCase.createMock(?cigre.description.ICodeDescriptor);
            setupDefaultMock(testCase, behavior, "StepInterface", stepIface);

            desc = makeModelDescription();
            desc.analyse(mock);

            testCase.verifyNumElements(desc.StepInputs, 2, ...
                "StepInputs must contain one Variable per function argument");
        end

    end

end

% --- Local helpers --------------------------------------------------------

function desc = makeModelDescription()
% Construct a ModelDescription with explicit folders to avoid Simulink.
desc = cigre.description.ModelDescription("MyModel", ...
    "CIGREInterfaceName", "MyWrapper", ...
    "CodeGenFolder", tempdir(), ...
    "WorkFolder", tempdir());
end

function [internalVars, inputVars, outputVars] = makeDefaultCodeInfoVars()
% Minimal internal-data set: one RTM struct pointer ending in _M plus one
% DWork struct. getRTMStruct requires exactly one _M variable to succeed.
rtmVar = cigre.description.Variable(...
    "SimulinkName", "MyWrapper_M", ...
    "ExternalName", "MyWrapper_M", ...
    "Type", "RT_MODEL_MyModel_T", ...
    "Pointers", "*");
dwVar = cigre.description.Variable(...
    "SimulinkName", "localDW", ...
    "ExternalName", "localDW", ...
    "Type", "DW_MyModel_T", ...
    "Pointers", "*");
internalVars = [rtmVar, dwVar];
inputVars = cigre.description.Variable.empty(1, 0);
outputVars = cigre.description.Variable.empty(1, 0);
end

function setupDefaultMock(testCase, behavior, nvp)
% Configure all CodeDescriptor methods required by analyse.
% Named pairs override defaults:
%   Metadata       - ModelMetadata (default: empty)
%   InitName       - string, initialise function name (default: "")
%   StepName       - string, step function name (default: "")
%   TerminateName  - string, terminate function name (default: "")
%   StepInterface  - FunctionInterface for step (overrides StepName)
%   Inputs         - Variable array for inports (default: empty)
%   Outputs        - Variable array for outports (default: empty)

arguments
    testCase
    behavior
    nvp.Metadata (1,1) cigre.description.ModelMetadata = cigre.description.ModelMetadata()
    nvp.InitName (1,1) string = ""
    nvp.StepName (1,1) string = ""
    nvp.TerminateName (1,1) string = ""
    nvp.StepInterface = cigre.description.FunctionInterface.empty(1,0)
    nvp.Inputs (1,:) cigre.description.Variable = cigre.description.Variable.empty(1,0)
    nvp.Outputs (1,:) cigre.description.Variable = cigre.description.Variable.empty(1,0)
end

[internalVars, inputVars, outputVars] = makeDefaultCodeInfoVars();

testCase.assignOutputsWhen(behavior.getModelMetadata.withAnyInputs(), nvp.Metadata);

% Minimal header/source with no timing bridge to keep tests independent
testCase.assignOutputsWhen(behavior.getWrapperHeaderCode.withAnyInputs(), ...
    "/* no RTM struct */");
testCase.assignOutputsWhen(behavior.getWrapperSourceCode.withAnyInputs(), ...
    "/* no rate_scheduler */");

testCase.assignOutputsWhen(behavior.getCodeInfoVariables.withAnyInputs(), ...
    internalVars, inputVars, outputVars);

testCase.assignOutputsWhen(behavior.getInports.withAnyInputs(), nvp.Inputs);
testCase.assignOutputsWhen(behavior.getOutports.withAnyInputs(), nvp.Outputs);
testCase.assignOutputsWhen(behavior.getParameters.withAnyInputs(), ...
    cigre.description.Variable.empty(1, 0));

testCase.assignOutputsWhen(behavior.getModelRefInitializeInterface.withAnyInputs(), ...
    makeFunctionInterface(""));
testCase.assignOutputsWhen(behavior.getInitializeInterface.withAnyInputs(), ...
    makeFunctionInterface(nvp.InitName));

if isempty(nvp.StepInterface)
    stepInterface = makeFunctionInterface(nvp.StepName);
else
    stepInterface = nvp.StepInterface;
end

testCase.assignOutputsWhen(behavior.getOutputInterface.withAnyInputs(), ...
    stepInterface);
testCase.assignOutputsWhen(behavior.getTerminateInterface.withAnyInputs(), ...
    makeFunctionInterface(nvp.TerminateName));
end

function iface = makeFunctionInterface(name)
% Build a zero-argument FunctionInterface, or empty if name is "".
if name == ""
    iface = cigre.description.FunctionInterface();
else
    iface = cigre.description.FunctionInterface("Name", name);
end
end
