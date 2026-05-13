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
                cleanups = setAutoToolchain(ModelName); %#ok<NASGU>
            end

            here = pwd;
            [desc, dll, c] = cigre.buildDLL(ModelName, ...
                "SkipBuild", ~doCompile, ...
                "CodeGenFolder", here, ...
                "BusAs", BusAs, ...
                buildArgs{:}); %#ok<ASGLU>

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

        function tVSBuild(testCase, ModelName, Snapshot, BusAs)

            testCase.loadData(ModelName);

            import matlab.unittest.fixtures.WorkingFolderFixture

            fixture.Folder = fullfile(cigreRoot, "test", "VS_Build", "VSBuild_" + ModelName);
            if ~isfolder(fixture.Folder)
                mkdir(fixture.Folder);
            end

            % Resulting files go in build folder
            here = pwd;
            cd(fixture.Folder);
            testCase.addTeardown(@() cd(here));

            testCase.applyCodeGenFixture(fullfile(pwd));

            % See tBuild: same mechanism for picking up a per-model
            % parameter config from the working folder.
            modelPath = which(ModelName + ".slx");
            configPath = fullfile(fileparts(modelPath), "ParameterConfig.xlsx");
            buildArgs = {};
            if isfile(configPath)
                buildArgs = {"ParameterConfigFile", configPath};
            end

            % Generate the code only
            desc = cigre.buildDLL(ModelName, "SkipBuild", true, "BusAs", BusAs, buildArgs{:});

            testCase.ModelDescription = desc;

            testCase.defineInputsAndParameters(desc);

            % Wrapper IO and baseline should match Simulink
            baseline = testCase.captureBaseline(desc.CIGREInterfaceName);

            % Build manually in Visual Studio following the instruction herein
            dll = testCase.doVSBuild(ModelName);

            % Extract the dll and header
            addpath(fullfile(pwd, "x64", "Debug"));
            addpath(fullfile(pwd, "slprj"));

            doRun = @() runDLL(testCase, dll, Snapshot, "VSBuild", true, "TwoData", false);

            result = testCase.runParallel(doRun, "PauseBeforeRun", true);

            baseline = timetable2table(baseline, 'ConvertRowTimes', false);
            baseline.Properties.VariableNames = result.Properties.VariableNames;
            baseline.Properties.VariableContinuity = [];

            testCase.verifyEqual(result, baseline, "RelTol", 1e-10)

        end

    end

    methods

        function dll = doVSBuild(testCase, modelName)
            arguments
                testCase
                modelName (1,1) string
            end

            dll = modelName + "_CIGRE.dll";
            clipboard("copy", dll);

            src = fullfile(cigreRoot, "src\CIGRESource");
            clipboard("copy", src);

            % manually create in VS
            fld =  fullfile(cigreRoot(), "\src\CIGRESource;");
            fld = fld + genpath(pwd + "\slprj\cigre\");
            fld = fld + fullfile(pwd + "\slprj\ert\_sharedutils") + ";";
            fld = fld + fullfile(matlabroot, "extern", "include")+";";
            fld = fld + fullfile(matlabroot, "simulink", "include") + ";";
            fld = fld + fullfile(matlabroot, "rtw\c\src") + ";";
            fld = fld + fullfile(pwd, modelName + "_wrap_cigre_rtw");
            %clipboard("copy", fld);

            keyboard %#ok<KEYBOARDFUN>

        end

        function defineInputsAndParameters(testCase, desc, nvp)
            arguments
                testCase
                desc
                nvp.TestTime (1,1) double = NaN
                nvp.ParameterConfig (1,1) cigre.config.ParameterConfiguration = cigre.config.ParameterConfiguration()
            end

            mdlName = desc.ModelName;
            testCase.tempLoad(mdlName);

            %% Create an input object to match the input and parameter test data
            if ismissing(nvp.TestTime)
                stopTime = double(string(eval(get_param(mdlName, "StopTime"))));
            else
                stopTime = nvp.TestTime;
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

            %% Inputs
            testCase.Inputs = {};

            inputs = desc.Inputs;

            if isempty(testCase.InputData)

                for i = 1:numel(inputs)
                    c = inputs(i).BaseType;

                    d = inputs(i).Dimensions;
                    if isscalar(d)
                        d = [d, 1]; %#ok<AGROW>
                    end
                    thisVal = ones(d);

                    if c == "boolean"
                        iVal = (thisVal ~= 0);
                    else
                        iVal = cast(i * thisVal, c);
                    end

                    % This supports matrices
                    iVals = repelem({iVal}, numel(time), 1);
                    iVals = cat(3, iVals{:});
                    iVals = permute(iVals, [3,1,2]);

                    % timetable/table constructors require their N-V
                    % pair names as char vectors in legacy syntax.
                    thisInput = timetable(iVals, 'RowTimes', time, 'VariableNames', "Var" + i);

                    input{i} = thisInput;
                end

                input = [input{:}];

            else
                input = testCase.InputData;
            end

            warning("Custom input")

            input.Var1(:) = 0;
            input.Var1(thisInput.Time > seconds(50)) = 100;
            input.Var2(:) = 0;
            testCase.Inputs = input;
            

            %% Parameters
            testCase.SimulinkParameters = struct("Name", {}, "Value", {});
            testCase.CIGREParameters = struct("Name", {}, "Value", {});

            % Build SimulinkParameters from the top-level parameter tree using model defaults
            simulinkParams = desc.Parameters;
            for i = 1:numel(simulinkParams)
                simulinkParam = simulinkParams(i);
                c = simulinkParam.BaseType;
                simulinkVal = simulinkParam.DefaultValue;
                try
                    simulinkVal = cast(simulinkVal, c);
                catch
                    % Not castable, e.g. a struct — leave as-is
                end
                testCase.SimulinkParameters(i) = struct("Name", simulinkParam.SimulinkName, "Value", simulinkVal);
            end

            % Apply effective defaults from the config to SimulinkParameters so the
            % Simulink baseline uses the same values as the DLL — including values
            % that are hardcoded for hidden parameters
            allCigreParams = desc.CIGREParameters;
            [visibleParams, hiddenParams] = nvp.ParameterConfig.partitionParameters(allCigreParams);

            allEffectiveParams = [visibleParams, hiddenParams];
            for i = 1:numel(allEffectiveParams)
                p = allEffectiveParams(i);
                testCase.SimulinkParameters = testCase.applyEffectiveDefault(testCase.SimulinkParameters, p.SimulinkName, p.DefaultValue);
            end

            % CIGREParameters contains only visible parameters with effective defaults,
            % since hidden parameters are hardcoded in the DLL and absent from its interface
            for j = 1:numel(visibleParams)
                cigreParam = visibleParams(j);
                cigreVal = cigreParam.DefaultValue;
                try
                    if cigreParam.BaseType == "boolean"
                        cigreVal = boolean(cigreVal);
                    else
                        cigreVal = cast(cigreVal, cigreParam.BaseType);
                    end
                catch
                    warning("Could not cast CIGRE parameter " + cigreParam.CIGREName + " to type " + cigreParam.BaseType);
                end
                testCase.CIGREParameters(end+1) = struct("Name", cigreParam.CIGREName, "Value", cigreVal);
            end

        end

        function baseline = captureBaseline(testCase, mdlName)
            arguments
                testCase
                mdlName (1,1) string
            end

            %% Create an input object to match the input and parameter test data
            testCase.tempLoad(mdlName);
            simIn = Simulink.SimulationInput(mdlName);

            % Inputs
            try
                if verLessThan("MATLAB", "25.1") %#ok<VERLESSMATLAB>
                    inDS = createInputDataset(mdlName);
                else
                    inDS = createInputDataset(mdlName, "UpdateDiagram", false);
                end
                nInputs = numel(inDS.getElementNames());
            catch me
                % errors if no inputs
                if me.identifier == "sl_sta:editor:modelNoExternalInterface"
                    nInputs = 0;
                else
                    rethrow(me)
                end
            end

            testCase.assertTrue(size(testCase.Inputs, 2) == nInputs, "Number of test inputs does not match model");

            if nInputs > 0

                for i = 1:nInputs
                    input = testCase.Inputs(:, i);

                    if istimetable(input)
                        vals = input.Variables;
                        if numel(size(vals)) > 2
                            % With e.g. t times points, an input of t x m x n
                            % needs permuting to m x n x t
                            vals = permute(vals, [(2:numel(size(vals))), 1]);
                        end
                        input = timeseries(vals, seconds(input.Time));
                        input = input.setinterpmethod("nearest");
                        input = input.setuniformtime("StartTime", 0, "EndTime", seconds(max(testCase.Inputs.Time(end))));
                        input.Name = testCase.Inputs.Properties.VariableNames{i};

                    end
                    inDS{i} = input;
                end

                simIn = simIn.setExternalInput(inDS);
            end

            % Parameters
            params = testCase.SimulinkParameters;

            % Model arguments
            ip = get_param(simIn.ModelName + "/mdl", "InstanceParameters");
            for i = 1:numel(params)
                name = testCase.SimulinkParameters(i).Name;
                val = testCase.SimulinkParameters(i).Value;
                val = char(util.valToString(val)); % Parameter value needs to be a char on the input object
                idx = (string({ip.Name}) == name);
                if any(idx)
                    ip(idx).Value = val;
                else
                    % In model workspace
                    mdl = erase(mdlName, "_wrap");
                    param = util.findParam(mdl, name);
                    if isa(param, "Simulink.data.dictionary.Entry")
                        simIn = simIn.setVariable(name, eval(val));
                    elseif isfield(param, "Value") || isprop(param, "Value")
                        param.Value = eval(val);
                        simIn = simIn.setVariable(name, param, "Workspace", mdl);
                    else
                        param = eval(value);
                        simIn = simIn.setVariable(name, param, "Workspace", mdl);
                    end

                end

            end

            if ~isempty(ip)
                % Newer MATLAB releases renamed the Path field on
                % InstanceParameters to FullPath; rename in-place so the
                % set works across versions.
                ipNew = arrayfun(@(x) renameStructField(x, "Path", "FullPath"), ip);
                simIn = simIn.setBlockParameter(simIn.ModelName + "/mdl", "InstanceParameters", ipNew);
            end

            % Simulation time
            simIn = setModelParameter(simIn, "StopTime", string(testCase.SimTime), "FixedStep", string(testCase.TimeStep));

            % Get the outputs
            results = sim(simIn);
            if isempty(results.yout{1}.Values.Data)
                % R2025a occasionally returns empty yout on the first
                % sim call for some models; re-running produces results.
                results = sim(simIn);
            end

            baseline = extractData(results);

            testCase.Outputs = baseline;

        end

        function result = runDLL(testCase, dllName, snapshot, nvp)
            arguments
                testCase
                dllName (1,1) string
                snapshot (1,1) logical = true
                nvp.VSBuild (1,1) logical = false
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

    methods (Access = private, Static)

        function simulinkParams = applyEffectiveDefault(simulinkParams, cigreSimulinkName, effectiveDefault)
            % Update the SimulinkParameters entry that corresponds to a flat CIGRE
            % SimulinkName. The root variable name (before the first '.' or '[')
            % identifies the entry; the remainder identifies the element to update.
            arguments
                simulinkParams  (1,:) struct
                cigreSimulinkName (1,1) string
                effectiveDefault (1,1) double
            end

            bracketPos = strfind(cigreSimulinkName, "[");
            dotPos = strfind(cigreSimulinkName, ".");
            splitPos = min([bracketPos, dotPos, strlength(cigreSimulinkName) + 1]);
            % Pad with a trailing space so extractBefore returns the full
            % name when the split index points past the end.
            rootName = extractBefore(cigreSimulinkName + " ", splitPos);

            entryIdx = find(string({simulinkParams.Name}) == rootName, 1);
            if isempty(entryIdx)
                return
            end

            currentValue = simulinkParams(entryIdx).Value;

            if ~isempty(bracketPos) && (isempty(dotPos) || bracketPos(1) < dotPos(1))
                % Array element, e.g. "p1[2]". The bracketed index is
                % zero-based (it came from the generated C code).
                zeroBasedIndex = str2double(extractBetween(cigreSimulinkName, "[", "]"));
                currentValue(zeroBasedIndex + 1) = cast(effectiveDefault, class(currentValue));
            elseif ~isempty(dotPos)
                fieldPath = extractAfter(cigreSimulinkName, ".");
                currentValue = test.system.tGenerateCigre.setNestedField(currentValue, fieldPath, effectiveDefault);
            else
                currentValue = cast(effectiveDefault, class(currentValue));
            end

            simulinkParams(entryIdx).Value = currentValue;
        end

        function s = setNestedField(s, fieldPath, value)
            % Recursively set a value in a nested struct given a dot-separated field path
            arguments
                s
                fieldPath (1,1) string
                value     (1,1) double
            end

            dotPos = strfind(fieldPath, ".");
            if isempty(dotPos)
                s.(fieldPath) = cast(value, class(s.(fieldPath)));
            else
                head = extractBefore(fieldPath, dotPos(1));
                tail = extractAfter(fieldPath, dotPos(1));
                s.(head) = test.system.tGenerateCigre.setNestedField(s.(head), tail, value);
            end
        end

    end

end

function cleanups = setAutoToolchain(modelName)
% setAutoToolchain Switch the top model and every referenced submodel
% to auto-detected toolchain. Returns an array of onCleanup objects
% that keep the affected systems loaded for the lifetime of the test;
% releasing them lets bdclose run unimpeded at teardown.
arguments
    modelName (1,1) string
end

[~, cTop] = util.loadSystem(modelName);
overrideToolchain(modelName);

refs = string(find_mdlrefs(modelName));
cleanups = {cTop};
for i = 1:numel(refs)
    if refs(i) == modelName
        continue
    end
    [~, cRef] = util.loadSystem(refs(i));
    overrideToolchain(refs(i));
    cleanups{end+1} = cRef; %#ok<AGROW>
end
end

function overrideToolchain(modelName)
% Apply the auto-detect override, then clear the dirty flag so the
% wrapper's save_system isn't blocked by SaveSystemWithDirtyReferencedModels.
% The in-memory override still takes effect; we just don't want Simulink
% to think the file on disk needs rewriting.
%
% When the model's active config is a reference (Simulink.ConfigSetRef),
% set_param on the model name fails with ConfigSetRef_SetParamNotAllowed;
% reach through to the underlying Simulink.ConfigSet and update there
% instead. Several models in test/models/ (NestedBus, Test_CP*) use this
% shape because they share a referenced config set with their submodels.
cs = getActiveConfigSet(modelName);
if ~isa(cs, "Simulink.ConfigSet")
    cs = cs.getRefConfigSet();
end
set_param(cs, "Toolchain", "Automatically locate an installed toolchain");

% UpdateModelReferenceTargets is being removed in a future release;
% MATLAB warns at every build when the saved value is anything other
% than "IfOutOfDate". Normalise it now so CI logs aren't full of the
% deprecation warning.
try
    set_param(cs, "UpdateModelReferenceTargets", "IfOutOfDate");
catch
    % Parameter or value missing on older releases - safe to skip.
end

set_param(modelName, "Dirty", "off");
end
