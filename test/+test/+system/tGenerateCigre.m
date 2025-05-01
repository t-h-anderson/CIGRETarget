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
        %ModelName = {"Test_LongNames_abcdefghijklmnopqrstuvwxyz"}
        %ModelName = {"Test_BlockIO"}
        %ModelName = {"Test_SignalObject"}
        %ModelName = {"Test_ParamModel"}
        %ModelName = {"Test_MultiInput"}
        %ModelName = {"Test_MultiOutput"}
        %ModelName = struct("Test_MIMO", "Test_MIMO")
        %ModelName = {"Test_FastRef"}
        %ModelName = {"Test_VectorIO"}
        %ModelName = {"NestedBus"}
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
    end
    
    properties
        Time
        SimTime
        TimeStep

        Inputs
        Outputs
        Parameters
        
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
        
        function tearDown(testCase)
            bdclose("all")
            Simulink.data.dictionary.closeAll('-discard')
        end
        
    end
    
    methods (Access = protected)
        
        function loadData(testCase, ModelName)

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
        
        function tBuild(testCase, ModelName, Bits, Snapshot, BusAs)
            
            testCase.loadData(ModelName);

            import matlab.unittest.fixtures.WorkingFolderFixture
            
            % Move to temp folder
            testCase.applyFixture(WorkingFolderFixture);
            
            cfg = Simulink.fileGenControl('getConfig');
            cfgOriginal = cfg;
            cfg.CodeGenFolder = fullfile(pwd);
            Simulink.fileGenControl('setConfig', 'config', cfg, 'createDir',true);
            testCase.addTeardown(@() Simulink.fileGenControl('setConfig', 'config', cfgOriginal));
            
            % TODO: Switch the toolchain to 32/64
            
            % Build the model
            here = pwd;
            [desc, dll, c] = cigre.buildDLL(ModelName, "SkipBuild", false, "CodeGenFolder", here, "BusAs", BusAs); %#ok<ASGLU>
            
            % Get the simulink baseline
            testCase.ModelDescription = desc;
            
            testCase.defineInputsAndParameters(desc);
            
            baseline = testCase.captureBaseline(desc.WrapperName); % Run the wrapper to easily support buses
            
            testCase.assertTrue(isfile(dll + ".dll"));
            
            % Run the dll if
            if Bits ~= "32"
                doRun = @() runDLL(testCase, dll, Snapshot);
                result = testCase.runParallel(doRun);
                
                % Compare the results
                baseline = timetable2table(baseline, "ConvertRowTimes",false);
                baseline.Properties.VariableNames = result.Properties.VariableNames;
                baseline.Properties.VariableContinuity = [];
                
                testCase.verifyEqual(result, baseline)
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
            
            cfg = Simulink.fileGenControl('getConfig');
            cfgOriginal = cfg;
            cfg.CodeGenFolder = fullfile(pwd);
            Simulink.fileGenControl('setConfig', 'config', cfg, 'createDir',true);
            testCase.addTeardown(@() Simulink.fileGenControl('setConfig', 'config', cfgOriginal));
            
            % Generate the code only
            desc = cigre.buildDLL(ModelName, "SkipBuild", true, "BusAs", BusAs);
            
            testCase.ModelDescription = desc;
            
            testCase.defineInputsAndParameters(desc);
            
            % Wrapper IO and baseline should match Simulink
            baseline = testCase.captureBaseline(desc.WrapperName);
            
            % Build manually in Visual Studio following the instruction herein
            dll = testCase.doVSBuild(ModelName);
            
            % Extract the dll and header
            addpath(fullfile(pwd, "x64", "Debug"));
            addpath(fullfile(pwd, "slprj"));
            
            doRun = @() runDLL(testCase, dll, Snapshot, "VSBuild", true, "TwoData", false);
            
            result = testCase.runParallel(doRun, "PauseBeforeRun", true);
            
            baseline = timetable2table(baseline, "ConvertRowTimes",false);
            baseline.Properties.VariableNames = result.Properties.VariableNames;
            baseline.Properties.VariableContinuity = [];
            
            testCase.verifyEqual(result, baseline, "RelTol", 1e-10)
            
        end
        
    end
    
    methods
        
        function dll = doVSBuild(testCase, modelName)
            
            dll = modelName + "_CIGRE.dll";
            
            src = fullfile(cigreRoot, "src\CIGRESource");
            clipboard("copy", src);
            
            % manually create in VS
            fld =  fullfile(cigreRoot(), "\src\CIGRESource;");
            fld = fld + genpath(pwd + "\slprj\cigre\");
            fld = fld + fullfile(pwd + "\slprj\ert\_sharedutils") + ";";
            fld = fld + fullfile(matlabroot, "extern", "include")+";";
            fld = fld + fullfile(matlabroot, "simulink", "include") + ";";
            fld = fld + fullfile(matlabroot, "rtw\c\src") + ";";
            fld = fld + fullfile(pwd, modelName + "_iwrap_wrap_cigre_rtw");
            %      clipboard("copy", fld);
            
            keyboard
            
        end
        
        function defineInputsAndParameters(testCase, desc, nvp)
            arguments
                testCase
                desc
                nvp.TestTime (1,1) double = NaN
            end
            
            mdlName = desc.ModelName;
            testCase.tempLoad(mdlName);

            %% Create an input object to match the input and parameter test data
            if ismissing(nvp.TestTime)
                stopTime = double(string(get_param(mdlName, "StopTime")));
            else
                stopTime = nvp.TestTime;
            end
            
            dt = get_param(mdlName, "FixedStep");
            if ~isnumeric(dt)
                try
                    dt = eval(dt);
                catch
                    try
                        dt = util.findParam(mdlName, dt);
                    catch
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
                    if numel(d) == 1
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

                    thisInput = timetable(iVals, 'RowTimes', time, 'VariableNames', "Var" + i);

                    input{i} = thisInput;
                end

                input = [input{:}];

            else
                input = testCase.InputData;
            end

            testCase.Inputs = input;
            
            %% Parameters
            testCase.Parameters = struct("Name", {}, "Value", {});
            
            params = desc.Parameters;
            for i = 1:numel(params)
                c = params(i).BaseType;
                
                value = i;
                
                try
                    val = cast(value, c);
                catch
                    % TODO: Not a Simulink.Parameter
                    val = cast(value, c);
                end
                testCase.Parameters(i) = struct("Name", params(i).GraphicalName, "Value", val);
            end
            
        end
        
        function baseline = captureBaseline(testCase, mdlName)
            
            %% Create an input object to match the input and parameter test data
            testCase.tempLoad(mdlName);
            simIn = Simulink.SimulationInput(mdlName);
            
            % Inputs
            try
                inDS = createInputDataset(mdlName);
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
                        input = input.setinterpmethod('nearest');
                        input = input.setuniformtime("StartTime", 0, "EndTime", seconds(max(testCase.Inputs.Time(end))));
                        input.Name = testCase.Inputs.Properties.VariableNames{i};
                    end
                    inDS{i} = input;
                end
                
                simIn = simIn.setExternalInput(inDS);
            end
            
            % Parameters
            % TODO: How do we access parameters?
            mdlRefs = string(find_mdlrefs(mdlName, "AllLevels", true));
            for i = 1:numel(mdlRefs)
                mdlRef = mdlRefs(i);
                testCase.tempLoad(mdlRef);
                params = Simulink.findVars(mdlRef);
                                
                for j = 1:numel(params)
                    name = params(j).Name;
                    idx = (string({testCase.Parameters.Name}) == name);
                    if ~any(idx)
                        % Parameter not in input set
                        continue
                    end
                    val = testCase.Parameters(idx).Value;
                    simIn = setVariable(simIn, name, val, "Workspace", mdlRef);
                end
            end

            simIn = setModelParameter(simIn, "StopTime", string(testCase.SimTime), "FixedStep", string(testCase.TimeStep));
            
            % Get the outputs
            results = sim(simIn);
            
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
            
            % Two data sets to check they work independently
            inputs = testCase.Inputs;
            inputs = table2cell(timetable2table(inputs)); % Input timetable is *very* slow so convery to cell
            inputs = inputs(:,2:end);

            outputs = testCase.Outputs;
            params = testCase.Parameters;

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
            
            %% Step
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

                % Test Snapshot Restart
                % Reload the dll
                instance1.clear();
                if nvp.TwoData
                    instance2.clear();
                end

                cigreDll.unload();
                c = cigreDll.load();

                instance1 = cigre.dll.InterfaceInstance(inputs, outputs, params, "IntStates", stateMemory1);
                if nvp.TwoData
                    instance2 = cigre.dll.InterfaceInstance(inputs, outputs, params, "IntStates", stateMemory2);
                end

                %% Step
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
            
            wasLoaded = bdIsLoaded(mdlName);
            load_system(mdlName);
            if ~wasLoaded
                testCase.addTeardown(@()close_system(mdlName, 0));
            end
            
        end
        
    end
    
end

