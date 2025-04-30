classdef tModelDescription < matlab.unittest.TestCase

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

    end

end