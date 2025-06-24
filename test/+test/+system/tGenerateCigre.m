classdef tGenerateCigre < test.util.WithParallelFixture
    
    properties (TestParameter)
        
        %% Model Name
        %ModelName
        %ModelName = test.util.getAllTestModels()
        %ModelName = {"Test_DataInput"}
        %ModelName = {"Test_SISO"}
        %ModelName = {"Test_StrtFunc"}
        %ModelName = {"Test_TopRef"}
        %ModelName = {"Test_BadNames"}
        %ModelName = {"Snap"}
        ModelName = {"Test_CP"}
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
        
        function tBuild(testCase, ModelName, Bits, Snapshot, BusAs, Toolchain)
            
            testCase.loadData(ModelName);

            import matlab.unittest.fixtures.WorkingFolderFixture
            
            % Move to temp folder
            testCase.applyFixture(WorkingFolderFixture);
            testCase.applyCodeGenFixture(fullfile(pwd));
                       
            % Switch the toolchain
            % tc = cigre.install("Toolchain", Toolchain, "Type", "64");
            %
            % l = Simulink.data.DataDictionary("TestConfig.sldd");
            % dd = Simulink.data.dictionary.open('TestConfig.sldd');
            % ds = dd.getSection('Configurations');
            % cf = ds.find('-class','Simulink.data.dictionary.Entry');
            % cs = cf.getValue();
            % set_param(cs, "Toolchain", tc);
            
            % Build the model
            here = pwd;
            [desc, dll, c] = cigre.buildDLL(ModelName, "SkipBuild", false, "CodeGenFolder", here, "BusAs", BusAs); %#ok<ASGLU>
            
            % Get the simulink baseline
            testCase.ModelDescription = desc;
            
            testCase.defineInputsAndParameters(desc);
            
            baseline = testCase.captureBaseline(desc.CIGREInterfaceName); % Run the wrapper to easily support buses
            
            testCase.assertTrue(isfile(dll + ".dll"));
            
            % Run the dll if
            if Bits ~= "32"
                doRun = @() runDLL(testCase, dll, Snapshot);
                result = testCase.runParallel(doRun);
                
                % Compare the results
                baseline = timetable2table(baseline, "ConvertRowTimes",false);
                baseline.Properties.VariableNames = result.Properties.VariableNames;
                baseline.Properties.VariableContinuity = [];
                baseline.Properties.VariableUnits = {};
                
                testCase.verifyEqual(result, baseline, "reltol", 1e-2)
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
            
            % Generate the code only
            desc = cigre.buildDLL(ModelName, "SkipBuild", true, "BusAs", BusAs);
            
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
            fld = fld + fullfile(pwd, modelName + "_wrap_cigre_rtw");
            %clipboard("copy", fld);
            
            keyboard %#ok<KEYBOARDFUN>
            
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
                        dt =  evalin('base', dt);
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
            testCase.SimulinkParameters = struct("Name", {}, "Value", {});
            testCase.CIGREParameters = struct("Name", {}, "Value", {});
            
            simulinkParams = desc.Parameters;
            for i = 1:numel(simulinkParams)
                simulinkParam = simulinkParams(i);
                simulinkName = simulinkParam.SimulinkName;
                                
                % Convert data type to base type
                c = simulinkParam.BaseType;
                simulinkVal = simulinkParam.DefaultValue;
                try
                    simulinkVal = cast(simulinkVal, c);
                catch
                    % Not castable, perhaps a struct
                end
                
                % Get Simulink Parameter for baseline test
                testCase.SimulinkParameters(i) = struct("Name", simulinkName, "Value", simulinkVal);
            end
            
            % Get CIGRE parameter for dll test
            cigreParams = desc.CIGREParameters;
            for j = 1:numel(cigreParams)
                cigreParam = cigreParams(j);
                cigreName = cigreParam.ExternalName; % e.g. a.b.c
                
                c = cigreParam.BaseType;
                cigreVal = cigreParam.DefaultValue;
                try
                    cigreVal = cast(cigreVal, c);
                catch
                    % Not castable
                    warning("Could not case CIGRE parameter " + cigreName + " to type " + c);
                end
                
                testCase.CIGREParameters(end+1) = struct("Name", cigreName, "Value", cigreVal);
                
            end

        end
        
        function baseline = captureBaseline(testCase, mdlName)
            
            %% Create an input object to match the input and parameter test data
            testCase.tempLoad(mdlName);
            simIn = Simulink.SimulationInput(char(mdlName));
            
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
                        input = input.setinterpmethod('nearest');
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
                val = char(util.valToString(val)); % Parameter value needs to be a sring on the input object
                idx = (string({ip.Name}) == name);
                if any(idx)
                    ip(idx).Value = val;
                else
                    % In model workspace
                    mdl = char(erase(mdlName, "_wrap"));
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
                ipNew = arrayfun(@(x) renameStructField(x, 'Path', 'FullPath'), ip);
                simIn = simIn.setBlockParameter(simIn.ModelName + "/mdl", "InstanceParameters", ipNew);
            end
            
            % Simulation time
            simIn = setModelParameter(simIn, "StopTime", string(testCase.SimTime), "FixedStep", string(testCase.TimeStep));
            
            % Get the outputs
            results = sim(simIn);
            if isempty(results.yout{1}.Values.Data)
                % There is a potential bug in R2025a where results are not
                % generated the first time the simulation is run
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
            
            % Two data sets to check they work independently
            inputs = retime(testCase.Inputs, 'regular', 'nearest', 'TimeStep', seconds(testCase.TimeStep));
            inputs = table2cell(timetable2table(inputs)); % Input timetable is *very* slow so convery to cell
            inputs = inputs(:,2:end);

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
                c = cigreDll.load(); %#ok<NASGU>

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

        function applyCodeGenFixture(testCase, pth)
            cfg = Simulink.fileGenControl('getConfig');

            oldCodeGenFolder = cfg.CodeGenFolder;
            oldCacheFolder = cfg.CacheFolder;

            cfg.CodeGenFolder = pth;
            cfg.CacheFolder = pth;
            try
                Simulink.fileGenControl('setConfig', 'config', cfg, 'createDir',true);
            catch
                warning("Set codegen and cache folder failed, likely due to interrupted previous build.")
            end

            % Reset to what we hard before, rather then bruteforce using
            % "reset"
            testCase.addTeardown(@() resetCFG(oldCodeGenFolder, oldCacheFolder));
            
            function resetCFG(oldCodeGenFolder, oldCacheFolder)
                % Path is relative... so hard to restore
                % cfgi = Simulink.fileGenControl('getConfig');
                % cfgi.CodeGenFolder = oldCodeGenFolder;
                % cfgi.CacheFolder = oldCacheFolder;
                % Simulink.fileGenControl('setConfig', 'config', cfgi)
                Simulink.fileGenControl('reset');
            end
        end
        
    end
    
end

