classdef tGenerateCigre < test.util.WithParallelFixture

    properties (TestParameter)

        %% Model Name
        %ModelName
        ModelName = test.util.getAllTestModels()
        %ModelName = {"Test_DataInput"}
        %ModelName = {"Test_SISO"}
        %ModelName = {"Test_StrtFunc"}
        %ModelName = {"Test_TopRef"}
        %ModelName = {"Test_BadNames"}
        %ModelName = {"Snap"}
        %ModelName = {"Test_CP_global"}
        %ModelName = {"Test_LongNames_abcdefghijklmnopqrstuvwxyz"}
        %ModelName = {"Test_BlockIO"}
        %ModelName = {"Test_SignalObject"}
        %ModelName = {"Test_ParamModel"}
        %ModelName = {"Test_MultiInput"}
        %ModelName = {"Test_MultiOutput"}
        %ModelName = struct("Test_MIMO", "Test_MIMO")
        %ModelName = {"Test_FastRef"}
        %ModelName = {"Test_VectorIO"}
        %ModelName = {"TestModel_meas"}
        %ModelName = {"Test_Enum"}

        %% Bits
        %Bits = struct("x64", "64", "x32", "32") % 32 bit run is not testable
        %Bits = struct("x32", "32") % not supported
        Bits = struct("x64", "64")

        %% Snapshot
        %Snapshot = struct("SnapshotOn", true, "SnapshotOff", false)
        %Snapshot = struct("SnapshotOff", false)
        Snapshot = struct("SnapshotOff", true)

        %% Wrapper bus type
        %BusAs = struct("Ports", "Ports", "Vector", "Vector")
        BusAs = struct("Vector", "Vector")

        %% Test each toolchain
        %         Toolchain = struct(...
        %             "VS2017", "Visual C++ 2017", ...
        %             "VS2019", "Visual C++ 2019", ...
        %             "VS2022", 'Visual C++ 2022', ...
        %             "MinGW", "MinGW")

        Toolchain = struct(...
            "MinGW", "MinGW")
    end

    properties
        Time
        SimTime
        TimeStep

        Inputs
        Outputs

        SimulinkParameters % Can contains structs
        CIGREParameters % Must be CIGRE data


        SrcFolder

        ModelDescription

        InputData
    end

    % Can be added once we have removed the 2020a requirement
    %     methods (TestParameterDefinition, Static)
    %
    %         function ModelName = initializeProperty()
    %
    %             ModelName = test.util.getAllTestModels();
    %
    %         end
    %
    %     end

    methods (TestClassSetup)

        function setup(testCase)
            testCase.SrcFolder = cigreRoot();

            root = cigreRoot();
            modelsFld = fullfile(root, "test", "models");

            testCase.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);

            % Copy models to here
            here = pwd;
            copyfile(modelsFld, here)

            % Add the models to the path
            pths = genpath(here);
            testCase.addTeardown(@() rmpath(pths));
            addpath(pths);

        end

    end

    methods (TestClassTeardown)

        function tearDown(testCase) %#ok<MANU>
            bdclose("all")
            Simulink.data.dictionary.closeAll("-discard")
        end

    end

    methods (Access = protected)

        function loadData(testCase, ModelName)
            arguments
                testCase
                ModelName (1,1) string
            end

            file = ModelName + "_input.mat";
            if string(which(file)) ~= ""
                data = load(file);

                f = string(fields(data));
                data = data.(f(1));

                testCase.InputData = data;
            else
                testCase.InputData = [];
            end
        end

    end

    methods (Test)

        function tBuild(testCase, ModelName, Bits, Snapshot, BusAs, Toolchain)

            % Pre-flight: confirm the model can be loaded on this
            % MATLAB release. Models saved with a newer version stamp
            % cannot be opened on older runners; report Incomplete
            % rather than Errored so the failure is informational and
            % surfaces in the test report instead of being hidden as a
            % filtered-out parameter.
            try
                [~, cPre] = util.loadSystem(ModelName); %#ok<NASGU>
            catch me
                testCase.assumeFail("Cannot load '" + ModelName + "' on " ...
                    + string(version("-release")) + ": " + me.message);
                return
            end

            testCase.loadData(ModelName);

            import matlab.unittest.fixtures.WorkingFolderFixture

            % Move to temp folder
            testCase.applyFixture(WorkingFolderFixture);
            testCase.applyCodeGenFixture(fullfile(pwd));

            % which() resolves the model after TestClassSetup copies it
            % into the working folder; this picks up any sibling
            % ParameterConfig.xlsx that should drive the build.
            modelPath = which(ModelName + ".slx");
            configPath = fullfile(fileparts(modelPath), "ParameterConfig.xlsx");
            buildArgs = {};
            paramConfig = cigre.config.ParameterConfiguration();
            if isfile(configPath)
                buildArgs = {"ParameterConfigFile", configPath};
                paramConfig = cigre.config.ParameterConfiguration.fromFile(configPath);
            end

            % The registered CIGRE toolchains produce a Windows DLL, so
            % only the Windows leg can compile and run the artefact.
            % Off-Windows we still want to exercise code generation
            % (catches TLC and analyseModel regressions) but stop short
            % of the make step and skip the baseline comparison.
            doCompile = ispc;

            % The saved test models reference Windows-only CIGRE
            % toolchains (e.g. "CIGRE DLL - Microsoft Visual C++ 2019
            % ...") which aren't in the registry on a Linux runner.
            % Override the toolchain on the source model (and any
            % referenced submodels) to auto-detect; the wrapper copies
            % this config so the override propagates into the build.
            if ~doCompile
                cleanups = test.util.setAutoToolchain(ModelName); %#ok<NASGU>
            end

            here = pwd;
            try
                [desc, dll, c] = cigre.buildDLL(ModelName, ...
                    "SkipBuild", ~doCompile, ...
                    "CodeGenFolder", here, ...
                    "BusAs", BusAs, ...
                    buildArgs{:}); %#ok<ASGLU>
            catch me
                if test.util.isKnownReleaseLimitation(me)
                    testCase.assumeFail("Skipping '" + ModelName + "' on " ...
                        + string(version("-release")) + ": " + me.message);
                    return
                end
                rethrow(me)
            end

            testCase.ModelDescription = desc;

            if doCompile
                % Get the simulink baseline
                testCase.defineInputsAndParameters(desc, "ParameterConfig", paramConfig);
                baseline = testCase.captureBaseline(desc.CIGREInterfaceName);

                testCase.assertTrue(isfile(dll + ".dll"));

                if Bits ~= "32"
                    doRun = @() runDLL(testCase, dll, Snapshot);
                    result = testCase.runParallel(doRun);

                    baseline = timetable2table(baseline, 'ConvertRowTimes', false);
                    baseline.Properties.VariableNames = result.Properties.VariableNames;
                    baseline.Properties.VariableContinuity = [];
                    baseline.Properties.VariableUnits = {};

                    testCase.verifyEqual(result, baseline, "reltol", 1e-2)
                end
            else
                % Codegen-only: verify the CIGRE-side C source landed in
                % the expected build folder. The cigre_make_rtw_hook
                % writes it under slprj/cigre.
                generatedC = fullfile(here, "slprj", "cigre", desc.ModelName + "_CIGRE.c");
                testCase.assertTrue(isfile(generatedC), ...
                    "Expected generated CIGRE source not found: " + generatedC);
            end

            clear c;

        end

    end

    methods (Test, TestTags = "Manual")

        function tVSBuild(testCase, ModelName, BusAs)
            % End-to-end Visual Studio debug build. Tagged Manual because
            % MSBuild is Windows-only and CI runs on Linux; on a Windows
            % box this test runs unattended (cigre.buildDLL(Debug=true)
            % drives MSBuild; cigre.internal.runDebugDLL with
            % PauseBeforeRun=false skips the VS Attach pause). For an
            % interactive debug session, call those two entry points by
            % hand with PauseBeforeRun=true.

            testCase.loadData(ModelName);

            workFolder = fullfile(cigreRoot, "test", "VS_Build", "VSBuild_" + ModelName);
            if ~isfolder(workFolder)
                mkdir(workFolder);
            end
            testCase.applyCodeGenFixture(workFolder);

            % Same per-model ParameterConfig.xlsx lookup as tBuild.
            modelPath = which(ModelName + ".slx");
            configPath = fullfile(fileparts(modelPath), "ParameterConfig.xlsx");
            buildArgs = {};
            if isfile(configPath)
                buildArgs = {"ParameterConfigFile", configPath};
            end

            [desc, dll] = cigre.buildDLL(ModelName, ...
                "Debug", true, ...
                "BusAs", BusAs, ...
                "CodeGenFolder", string(workFolder), ...
                buildArgs{:});
            testCase.ModelDescription = desc;

            testCase.defineInputsAndParameters(desc);
            baseline = testCase.captureBaseline(desc.CIGREInterfaceName);

            % runDebugDLL introspects the DLL header for sample time and
            % port layout; it only needs the inputs and parameters here.
            result = cigre.internal.runDebugDLL(dll, ...
                "Inputs", testCase.Inputs, ...
                "Parameters", testCase.CIGREParameters, ...
                "PauseBeforeRun", false);

            baseline = timetable2table(baseline, 'ConvertRowTimes', false);
            baseline.Properties.VariableNames = result.Properties.VariableNames;
            baseline.Properties.VariableContinuity = [];

            testCase.verifyEqual(result, baseline, "RelTol", 1e-10)
        end

    end

    methods

        function defineInputsAndParameters(testCase, desc, nvp)
            arguments
                testCase
                desc
                nvp.TestTime (1,1) double = NaN
                nvp.ParameterConfig (1,1) cigre.config.ParameterConfiguration = cigre.config.ParameterConfiguration()
            end

            testCase.tempLoad(desc.ModelName);
            testCase.computeSimulationTiming(desc, nvp.TestTime);
            testCase.generateTestInputs(desc);
            testCase.gatherParameters(desc, nvp.ParameterConfig);
        end

        function baseline = captureBaseline(testCase, mdlName)
            arguments
                testCase
                mdlName (1,1) string
            end

            testCase.tempLoad(mdlName);
            baseline = cigre.util.captureSimulinkBaseline(mdlName, ...
                testCase.Inputs, testCase.SimulinkParameters, ...
                testCase.SimTime, testCase.TimeStep);
            testCase.Outputs = baseline;
        end

        function result = runDLL(testCase, dllName, snapshot, nvp)
            arguments
                testCase
                dllName (1,1) string
                snapshot (1,1) logical = true
                nvp.TwoData (1,1) logical = true
            end

            cigreDll = cigre.dll.CigreDLL(dllName);

            try
                cObj = cigreDll.load(); %#ok<NASGU>
            catch me
                testCase.assertFalse(true, me.message);
            end

            % Two parallel datasets verify that DLL instances do not
            % share state through hidden globals.
            % retime parses N-V parameter names as char vectors in
            % older releases; keep TimeStep quoted to match.
            inputs = retime(testCase.Inputs, 'regular', 'nearest', 'TimeStep', seconds(testCase.TimeStep));
            % Indexing into a timetable per timestep is much slower than
            % into a cell, so convert once up front.
            inputs = table2cell(timetable2table(inputs));
            inputs = inputs(:, 2:end);

            outputs = testCase.Outputs;
            params = testCase.CIGREParameters;

            instance1 = cigre.dll.InterfaceInstance(inputs, outputs, params);
            if nvp.TwoData
                instance2 = cigre.dll.InterfaceInstance(inputs, outputs, params);
            end

            %% Initialise
            cigreDll.initialise(instance1);
            if nvp.TwoData
                cigreDll.initialise(instance2);
            end

            nTimeTotal = size(testCase.Outputs, 1);

            if snapshot
                % Take one timestep then snapshot
                nTimeBeforeSnapshot = 5;
            else
                nTimeBeforeSnapshot = nTimeTotal;
            end

            results = cell(1, nTimeTotal);
            for i = 1:nTimeBeforeSnapshot
                instance1.updateInputs(inputs, "Row", i)
                results{i} = cigreDll.step(instance1);
            end

            if snapshot

                stateMemory1 = instance1.StateMemory;
                if nvp.TwoData
                    stateMemory2 = instance2.StateMemory;
                end

                % Snapshot restart: unload, reload, and reconstruct the
                % instances from the saved int-state buffers. The result
                % stream should be continuous across the boundary.
                instance1.clear();
                if nvp.TwoData
                    instance2.clear();
                end

                cigreDll.unload();
                c = cigreDll.load(); %#ok<NASGU>

                instance1 = cigre.dll.InterfaceInstance(inputs, outputs, params, "IntStates", stateMemory1);
                if nvp.TwoData
                    instance2 = cigre.dll.InterfaceInstance(inputs, outputs, params, "IntStates", stateMemory2);
                end

                for i = (nTimeBeforeSnapshot + 1):nTimeTotal
                    instance1.updateInputs(inputs, "Row", i)
                    results{i} = cigreDll.step(instance1);
                end
            end

            results = vertcat(results{:});

            result = cell2table(results);

            instance1.clear();
            if nvp.TwoData
                instance2.clear();
            end

        end

        function tempLoad(testCase, mdlName)
            arguments
                testCase
                mdlName (1,1) string
            end

            wasLoaded = bdIsLoaded(mdlName);
            load_system(mdlName);
            if ~wasLoaded
                testCase.addTeardown(@()close_system(mdlName, 0));
            end

        end

        function applyCodeGenFixture(testCase, pth)
            arguments
                testCase
                pth (1,1) string
            end
            cfg = Simulink.fileGenControl("getConfig");

            oldCodeGenFolder = cfg.CodeGenFolder; %#ok<NASGU>
            oldCacheFolder = cfg.CacheFolder; %#ok<NASGU>

            % Simulink.FileGenConfig's setters reject strings and require
            % a char vector specifically.
            cfg.CodeGenFolder = char(pth);
            cfg.CacheFolder = char(pth);
            try
                Simulink.fileGenControl("setConfig", "config", cfg, "createDir", true);
            catch
                warning("Set codegen and cache folder failed, likely due to interrupted previous build.")
            end

            % Paths get normalised relative to the model folder, so the
            % originals cannot be restored verbatim; fall back to reset.
            testCase.addTeardown(@() Simulink.fileGenControl("reset"));
        end

    end

    methods (Access = private)

        function computeSimulationTiming(testCase, desc, testTime)
            arguments
                testCase
                desc
                testTime (1,1) double = NaN
            end

            mdlName = desc.ModelName;

            if ismissing(testTime)
                stopTime = double(string(eval(get_param(mdlName, "StopTime"))));
            else
                stopTime = testTime;
            end

            dt = get_param(mdlName, "FixedStep");
            if ~isnumeric(dt)
                try
                    try
                        dt = eval(dt);
                    catch
                        dt = evalin("base", dt);
                    end
                catch
                    [~, dt] = util.findParam(mdlName, dt);
                    if dt == 0
                        dt = 0.1;
                    end
                end
            end

            timeStep = dt;
            time = seconds(0:timeStep:stopTime)';

            testCase.SimTime = stopTime;
            testCase.TimeStep = timeStep;
            testCase.Time = time;
        end

        function generateTestInputs(testCase, desc)
            arguments
                testCase
                desc
            end

            time = testCase.Time;

            testCase.Inputs = {};

            if isempty(testCase.InputData)
                input = cigre.internal.generateDefaultInputs(desc, time);
            else
                input = testCase.InputData;
            end

            warning("Custom input")

            input.Var1(:) = 0;
            input.Var1(time > seconds(50)) = 100;
            input.Var2(:) = 0;
            testCase.Inputs = input;
        end

        function gatherParameters(testCase, desc, parameterConfig)
            arguments
                testCase
                desc
                parameterConfig (1,1) cigre.config.ParameterConfiguration
            end

            [testCase.SimulinkParameters, testCase.CIGREParameters] = ...
                cigre.internal.resolveParameters(desc, parameterConfig);
        end

    end

end
