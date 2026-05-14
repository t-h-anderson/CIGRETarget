function buildDLLWithDebug(model, nvp)
% buildDLLWithDebug Generate a CIGRE DLL ready for manual VS debugging.
%
%   cigre.internal.buildDLLWithDebug(model, "InputsFile", "myInputs.mat")
%   cigre.internal.buildDLLWithDebug(model, ...
%       "InputsFile", "myInputs.mat", "ParametersFile", "myParams.xlsx")
%
% Sets up a working folder, emits CIGRE-target code for the wrapper,
% writes a ready-to-open .sln + .vcxproj (via writeVSProject) configured
% for Debug | x64 | DynamicLibrary with the correct include paths, and
% pauses (via keyboard) so a super user can open the solution in Visual
% Studio, hit Build > Build Solution, set breakpoints, and step through.
% After the user resumes, the freshly-built DLL is loaded and stepped
% through the inputs from InputsFile; if Compare=true (the default) the
% DLL output is verified against a Simulink baseline run on the same
% inputs and parameters.
%
% This is the production sibling of test.system.tGenerateCigre.tVSBuild;
% it ships in src/ so users who don't have the test harness available
% (e.g. installed toolbox users) can still drive the workflow.
%
% Inputs:
%   model - top-level model name. The wrapper "<model>_wrap" is built.
%
% Name-Value Arguments:
%   InputsFile     - path to a .mat file containing a single timetable
%                    variable (use cigre.util.captureInputsFromSimulink
%                    to generate one). Required.
%   ParametersFile - path to a ParameterConfig.xlsx (use
%                    cigre.util.captureParametersFromSimulink). Optional;
%                    if omitted the model's defaults are used.
%   Compare        - if true (default), capture a Simulink baseline and
%                    diff the DLL output against it after the user
%                    finishes the VS build. Set false to skip the
%                    baseline and just run the DLL once the user has
%                    finished.
%   BusAs          - wrapper bus-handling mode (default "Vector").
%   WorkFolder     - working directory the build is staged in (default
%                    tempdir/<model>_dbg_<pid>).
%   RelTol         - relative tolerance for the baseline comparison
%                    (default 1e-10).
arguments
    model (1,1) string
    nvp.InputsFile (1,1) string
    nvp.ParametersFile (1,1) string = string(missing)
    nvp.Compare (1,1) logical = true
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.WorkFolder (1,1) string = ...
        string(fullfile(tempdir, model + "_dbg_" + string(feature("getpid"))))
    nvp.RelTol (1,1) double = 1e-10
end

if ~isfile(nvp.InputsFile)
    error("CIGRE:buildDLLWithDebug:InputsFileMissing", ...
        "InputsFile does not exist: %s", nvp.InputsFile);
end

if ~isfolder(nvp.WorkFolder)
    mkdir(nvp.WorkFolder);
end
here = pwd;
cd(nvp.WorkFolder);
cCwd = onCleanup(@() cd(here)); %#ok<NASGU>

% Generate code (no make), with the optional parameter override file.
buildArgs = {};
if ~ismissing(nvp.ParametersFile)
    if ~isfile(nvp.ParametersFile)
        error("CIGRE:buildDLLWithDebug:ParametersFileMissing", ...
            "ParametersFile does not exist: %s", nvp.ParametersFile);
    end
    buildArgs = {"ParameterConfigFile", nvp.ParametersFile};
end

desc = cigre.buildDLL(model, ...
    "SkipBuild", true, ...
    "CodeGenFolder", string(pwd), ...
    "BusAs", nvp.BusAs, ...
    buildArgs{:});

% Load saved inputs. loadData-style: the .mat is expected to contain a
% single timetable; we take the first variable.
loaded = load(nvp.InputsFile);
inputsField = string(fieldnames(loaded));
inputs = loaded.(inputsField(1));
if ~istimetable(inputs)
    error("CIGRE:buildDLLWithDebug:InputsNotTimetable", ...
        "Variable '%s' in %s is not a timetable.", inputsField(1), nvp.InputsFile);
end

% Reconstruct a Simulink/CIGRE parameter pair from the model description
% and the supplied ParameterConfig (defaults are used if none was given).
if ismissing(nvp.ParametersFile)
    paramConfig = cigre.config.ParameterConfiguration();
else
    paramConfig = cigre.config.ParameterConfiguration.fromFile(nvp.ParametersFile);
end
[simulinkParameters, cigreParameters] = resolveParameters(desc, paramConfig);

% Sim timing taken from the model. The inputs timetable's time vector
% must match this for the baseline comparison to line up cleanly.
[stopTime, timeStep] = readModelTiming(model);

% Always capture the Simulink baseline: the DLL runner needs an
% outputs-shape allocator (cigre.dll.DataMap.create reads sizes from
% the supplied container), and the baseline timetable is the natural
% candidate. The Compare flag only governs whether the post-run diff is
% reported as pass/fail.
baseline = cigre.internal.captureSimulinkBaseline( ...
    desc.CIGREInterfaceName, inputs, simulinkParameters, stopTime, timeStep);

% Hand off to the user. Generate a ready-to-open VS solution + project
% so the only thing left to do on the Windows side is Build > Build
% Solution, set breakpoints, and resume MATLAB.
dllName = model + "_CIGRE";
slnPath = cigre.internal.writeVSProject(model, string(pwd));
printVSBuildInstructions(slnPath);

fprintf("\n*** Build the DLL in Visual Studio, then 'dbcont' to resume ***\n");
keyboard %#ok<KEYBOARDFUN>

% Resume: the DLL should now be on the file system. Pull it from the
% standard x64\Debug folder VS writes to.
addpath(fullfile(pwd, "x64", "Debug"));
addpath(fullfile(pwd, "slprj"));

result = runDLL(dllName, inputs, cigreParameters, baseline, timeStep);

if ~nvp.Compare
    fprintf("\nDLL run complete (%d rows). Compare disabled; result is in cigre_debug_result.\n", height(result));
    assignin("base", "cigre_debug_result", result);
    return
end

% Diff against the Simulink baseline.
baselineTable = timetable2table(baseline, 'ConvertRowTimes', false);
baselineTable.Properties.VariableNames = result.Properties.VariableNames;
baselineTable.Properties.VariableContinuity = [];

passed = isequaln(result, baselineTable);
if ~passed
    try
        % Numerical-tolerance comparison via the unittest constraint.
        import matlab.unittest.constraints.IsEqualTo
        import matlab.unittest.constraints.RelativeTolerance
        passed = IsEqualTo(baselineTable, "Within", RelativeTolerance(nvp.RelTol)) ...
            .satisfiedBy(result);
    catch
        passed = false;
    end
end

assignin("base", "cigre_debug_result", result);
assignin("base", "cigre_debug_baseline", baselineTable);
if passed
    fprintf("\nDLL output matches Simulink baseline within RelTol=%g.\n", nvp.RelTol);
else
    fprintf("\nDLL output DIFFERS from Simulink baseline. Compare cigre_debug_result vs cigre_debug_baseline in the base workspace.\n");
end

end


function [simulinkParameters, cigreParameters] = resolveParameters(desc, paramConfig)
% Build the SimulinkParameters / CIGREParameters structs the same way
% tGenerateCigre's gatherParameters does, but parameterised purely on
% the descriptor and config (no testCase state).
simulinkParameters = struct("Name", {}, "Value", {});
cigreParameters = struct("Name", {}, "Value", {});

simulinkParams = desc.Parameters;
for i = 1:numel(simulinkParams)
    p = simulinkParams(i);
    val = p.DefaultValue;
    try
        val = cast(val, p.BaseType);
    catch
        % Not castable (e.g. a struct default) - leave as-is.
    end
    simulinkParameters(i) = struct("Name", p.SimulinkName, "Value", val);
end

allCigreParams = desc.CIGREParameters;
[visibleParams, hiddenParams] = paramConfig.partitionParameters(allCigreParams);

% Visible + hidden defaults flow into SimulinkParameters; only visible
% are exposed as CIGREParameters (hidden are baked into the DLL).
for i = 1:numel([visibleParams, hiddenParams])
    all = [visibleParams, hiddenParams];
    p = all(i);
    simulinkParameters = applyEffectiveDefault(simulinkParameters, ...
        p.SimulinkName, p.DefaultValue);
end

for j = 1:numel(visibleParams)
    p = visibleParams(j);
    val = p.DefaultValue;
    try
        if p.BaseType == "boolean"
            val = boolean(val);
        else
            val = cast(val, p.BaseType);
        end
    catch
        warning("Could not cast CIGRE parameter %s to %s", p.CIGREName, p.BaseType);
    end
    cigreParameters(end+1) = struct("Name", p.CIGREName, "Value", val); %#ok<AGROW>
end
end


function simulinkParams = applyEffectiveDefault(simulinkParams, cigreSimulinkName, effectiveDefault)
% Mirror of test.system.tGenerateCigre.applyEffectiveDefault. The CIGRE
% SimulinkName may include array indexing or nested struct field paths;
% the root identifier matches an existing entry in simulinkParams.
arguments
    simulinkParams  (1,:) struct
    cigreSimulinkName (1,1) string
    effectiveDefault (1,1) double
end

bracketPos = strfind(cigreSimulinkName, "[");
dotPos = strfind(cigreSimulinkName, ".");
splitPos = min([bracketPos, dotPos, strlength(cigreSimulinkName) + 1]);
rootName = extractBefore(cigreSimulinkName + " ", splitPos);

entryIdx = find(string({simulinkParams.Name}) == rootName, 1);
if isempty(entryIdx)
    return
end

currentValue = simulinkParams(entryIdx).Value;

if ~isempty(bracketPos) && (isempty(dotPos) || bracketPos(1) < dotPos(1))
    zeroBasedIndex = str2double(extractBetween(cigreSimulinkName, "[", "]"));
    currentValue(zeroBasedIndex + 1) = cast(effectiveDefault, class(currentValue));
elseif ~isempty(dotPos)
    fieldPath = extractAfter(cigreSimulinkName, ".");
    currentValue = setNestedField(currentValue, fieldPath, effectiveDefault);
else
    currentValue = cast(effectiveDefault, class(currentValue));
end

simulinkParams(entryIdx).Value = currentValue;
end


function s = setNestedField(s, fieldPath, value)
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
    s.(head) = setNestedField(s.(head), tail, value);
end
end


function [stopTime, timeStep] = readModelTiming(mdlName)
arguments
    mdlName (1,1) string
end
[~, c] = util.loadSystem(mdlName); %#ok<ASGLU>
stopTime = double(string(eval(get_param(mdlName, "StopTime"))));
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
end


function printVSBuildInstructions(slnPath)
% Tell the user where the auto-generated solution lives and clipboard
% the path so they can paste it into Explorer / File > Open. Everything
% else (include dirs, output name, Debug | x64, DynamicLibrary
% configuration type) is baked into the .vcxproj by writeVSProject,
% so there is no per-build manual setup left.
fprintf("\n=== Visual Studio Debug Build ===\n");
fprintf("Open this solution in Visual Studio (path copied to clipboard):\n  %s\n", slnPath);
fprintf("Then Build > Build Solution. The DLL lands at:\n  %s\n", ...
    fullfile(fileparts(slnPath), "x64", "Debug"));
clipboard("copy", slnPath);
end


function result = runDLL(dllName, inputs, cigreParameters, outputs, timeStep)
% Simplified DLL runner: load, init, step row-by-row, unload.
%
% Mirror of test.system.tGenerateCigre.runDLL minus the snapshot/parallel
% logic, which is test-specific and not useful in a debug session. The
% outputs argument is used purely as a shape descriptor for
% cigre.dll.DataMap.create; pass the captured Simulink baseline
% timetable so the allocator sees the right per-port types.
arguments
    dllName (1,1) string
    inputs timetable
    cigreParameters (1,:) struct
    outputs
    timeStep (1,1) double
end

cigreDll = cigre.dll.CigreDLL(dllName);
cObj = cigreDll.load(); %#ok<NASGU>

inputs = retime(inputs, 'regular', 'nearest', 'TimeStep', seconds(timeStep));
inputsCell = table2cell(timetable2table(inputs));
inputsCell = inputsCell(:, 2:end);  % drop the time column

instance = cigre.dll.InterfaceInstance(inputsCell, outputs, cigreParameters);
cigreDll.initialise(instance);

nSteps = size(outputs, 1);
results = cell(1, nSteps);
for i = 1:nSteps
    instance.updateInputs(inputsCell, "Row", i);
    results{i} = cigreDll.step(instance);
end

results = vertcat(results{:});
result = cell2table(results);

instance.clear();
end
