function buildDLLWithDebug(model, nvp)
% buildDLLWithDebug Generate a CIGRE DLL ready for VS debugging.
%
%   cigre.internal.buildDLLWithDebug(model)
%   cigre.internal.buildDLLWithDebug(model, "InputsFile", "myInputs.mat")
%   cigre.internal.buildDLLWithDebug(model, ...
%       "InputsFile", "myInputs.mat", "ParametersFile", "myParams.xlsx")
%
% Stages a working folder, emits CIGRE-target code for the wrapper,
% writes a ready-to-open .sln + .vcxproj (via writeVSProject) configured
% for Debug | x64 | DynamicLibrary with the correct include paths, and
% pauses (via keyboard) so the user can open the solution in Visual
% Studio and hit Build > Build Solution. On resume, the DLL plus a
% debug_session.mat capturing the inputs, parameters, and (optionally)
% Simulink baseline are zipped into <model>_CIGRE_session.zip, and
% cigre.internal.runDebugDLL is called on the zip. Repeated runs after
% rebuilds in VS are then just cigre.internal.runDebugDLL of the same
% zip - no need to re-run codegen.
%
% Both InputsFile and ParametersFile are optional, so the smallest
% smoke-test invocation is just buildDLLWithDebug("MyModel") - inputs
% default to a synthetic constant per Inport, parameters default to
% the model's saved values.
%
% This is the production sibling of test.system.tGenerateCigre.tVSBuild;
% it ships in src/ so users who don't have the test harness available
% can still drive the workflow.
%
% Inputs:
%   model - top-level model name. The wrapper "<model>_wrap" is built.
%
% Name-Value Arguments:
%   InputsFile     - path to a .mat file containing a single timetable
%                    variable (use cigre.util.captureInputsFromSimulink).
%                    Optional; if omitted, a synthetic input timetable
%                    is generated via cigre.internal.generateDefaultInputs.
%   ParametersFile - path to a ParameterConfig.xlsx (use
%                    cigre.util.captureParametersFromSimulink). Optional;
%                    if omitted the model's defaults are used.
%   Compare        - if true, capture a Simulink baseline and stash it
%                    in the session bundle so runDebugDLL can diff DLL
%                    output against it. Default false: the debug
%                    workflow is about stepping through, and the
%                    Simulink sim adds noticeable overhead.
%   BusAs          - wrapper bus-handling mode (default "Vector").
%   WorkFolder     - working directory the build is staged in (default
%                    tempdir/<model>_dbg_<pid>).
%   RelTol         - relative tolerance for the baseline comparison
%                    (default 1e-10); only used when Compare=true.
%   PlatformToolset - VS toolset for the generated project (default
%                    "v142"; see cigre.internal.writeVSProject).
%   WindowsTargetPlatformVersion - SDK version for the generated
%                    project (default "10.0").
arguments
    model (1,1) string
    nvp.InputsFile (1,1) string = string(missing)
    nvp.ParametersFile (1,1) string = string(missing)
    nvp.Compare (1,1) logical = false
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.WorkFolder (1,1) string = ...
        string(fullfile(tempdir, model + "_dbg_" + string(feature("getpid"))))
    nvp.RelTol (1,1) double = 1e-10
    nvp.PlatformToolset (1,1) string = "v142"
    nvp.WindowsTargetPlatformVersion (1,1) string = "10.0"
end

if ~ismissing(nvp.InputsFile) && ~isfile(nvp.InputsFile)
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

% Sim timing taken from the model. The inputs timetable's time vector
% must match this for the baseline comparison to line up cleanly; when
% we synthesise inputs below we use the same vector.
[stopTime, timeStep] = readModelTiming(model);
time = seconds(0:timeStep:stopTime)';

if ismissing(nvp.InputsFile)
    fprintf("No InputsFile supplied; generating synthetic defaults (input k = k * ones).\n");
    inputs = cigre.internal.generateDefaultInputs(desc, time);
else
    % loadData-style: the .mat is expected to contain a single
    % timetable; we take the first variable.
    loaded = load(nvp.InputsFile);
    inputsField = string(fieldnames(loaded));
    inputs = loaded.(inputsField(1));
    if ~istimetable(inputs)
        error("CIGRE:buildDLLWithDebug:InputsNotTimetable", ...
            "Variable '%s' in %s is not a timetable.", inputsField(1), nvp.InputsFile);
    end
end

% Reconstruct a Simulink/CIGRE parameter pair from the model description
% and the supplied ParameterConfig (defaults are used if none was given).
if ismissing(nvp.ParametersFile)
    paramConfig = cigre.config.ParameterConfiguration();
else
    paramConfig = cigre.config.ParameterConfiguration.fromFile(nvp.ParametersFile);
end
[simulinkParameters, cigreParameters] = resolveParameters(desc, paramConfig);

% Two paths for the outputs container that DataMap needs as a shape
% descriptor:
%   Compare=true  : run Simulink, use the resulting baseline timetable
%                   (so runDebugDLL can also diff against it later).
%   Compare=false : skip the Simulink sim (saves the round-trip
%                   overhead) and build a zeros-of-the-right-shape
%                   timetable from desc.Outputs instead.
if nvp.Compare
    baseline = cigre.internal.captureSimulinkBaseline( ...
        desc.CIGREInterfaceName, inputs, simulinkParameters, stopTime, timeStep);
    outputsShape = baseline;
else
    baseline = timetable.empty;
    outputsShape = generateOutputsShape(desc, time);
end

% Hand off to the user. Generate a ready-to-open VS solution + project
% so the only thing left to do on the Windows side is Build > Build
% Solution.
dllName = model + "_CIGRE";
slnPath = cigre.internal.writeVSProject(model, string(pwd), ...
    "PlatformToolset", nvp.PlatformToolset, ...
    "WindowsTargetPlatformVersion", nvp.WindowsTargetPlatformVersion);
printVSBuildInstructions(slnPath);

fprintf("\n*** Build the DLL in Visual Studio, then 'dbcont' to bundle and run ***\n");
keyboard %#ok<KEYBOARDFUN>

% Resume: the DLL should now be on disk under x64\Debug. Save the
% per-run state needed to reproduce a DLL invocation, then zip up the
% DLL + PDB + state into a single portable bundle. runDebugDLL only
% needs the bundle - the codegen folder can be deleted between
% sessions and the rerun still works.
sessionMat = fullfile(pwd, "debug_session.mat");
DllName = dllName;             %#ok<NASGU>
Inputs = inputs;               %#ok<NASGU>
CIGREParameters = cigreParameters; %#ok<NASGU>
Outputs = outputsShape;        %#ok<NASGU>
Baseline = baseline;           %#ok<NASGU>
TimeStep = timeStep;           %#ok<NASGU>
RelTol = nvp.RelTol;           %#ok<NASGU>
save(sessionMat, "DllName", "Inputs", "CIGREParameters", "Outputs", ...
    "Baseline", "TimeStep", "RelTol");

bundlePath = bundleDebugSession(nvp.WorkFolder, dllName);
fprintf("\nSession bundle: %s\n", bundlePath);
fprintf("Rerun without rebuilding: cigre.internal.runDebugDLL(""%s"")\n", bundlePath);
assignin("base", "cigre_debug_bundle", bundlePath);

% First run uses the same bundle path; subsequent reruns can just call
% runDebugDLL again.
cigre.internal.runDebugDLL(bundlePath, "Compare", nvp.Compare);

end


function bundlePath = bundleDebugSession(workFolder, dllName)
% Pack the DLL + PDB + debug_session.mat into a single zip alongside
% the work folder. flattenPaths so the .zip is a flat archive that
% extracts cleanly anywhere - runDebugDLL adds the extracted dir to
% the path.
bundlePath = fullfile(workFolder, dllName + "_session.zip");

dllPath = fullfile(workFolder, "x64", "Debug", dllName + ".dll");
pdbPath = fullfile(workFolder, "x64", "Debug", dllName + ".pdb");
sessionMat = fullfile(workFolder, "debug_session.mat");

if ~isfile(dllPath)
    error("CIGRE:buildDLLWithDebug:DLLMissing", ...
        "Expected %s after VS build, but it does not exist. Did the Build > Build Solution step succeed?", dllPath);
end

files = string(dllPath);
if isfile(pdbPath)
    files = [files; string(pdbPath)];
end
files = [files; string(sessionMat)];

zip(bundlePath, files);
end


function outputs = generateOutputsShape(desc, time)
% Synthesise a zeros timetable matching the wrapper's Outport interface.
% Used only to give cigre.dll.DataMap.create / InterfaceInstance the
% right per-port type and dimensions when no Simulink baseline is being
% captured. Mirrors generateDefaultInputs but uses Outports and zeros.
arguments
    desc
    time (:,1) duration
end

simOutputs = desc.Outputs;
n = numel(simOutputs);
if n == 0
    outputs = timetable.empty;
    return
end

cols = cell(1, n);
for i = 1:n
    spec = simOutputs(i);
    d = spec.Dimensions;
    if isscalar(d)
        d = [d, 1];
    end

    if spec.BaseType == "boolean"
        template = false(d);
    else
        template = zeros(d, spec.BaseType);
    end

    repl = repelem({template}, numel(time), 1);
    repl = cat(3, repl{:});
    repl = permute(repl, [3, 1, 2]);

    cols{i} = timetable(repl, 'RowTimes', time, 'VariableNames', "Var" + i);
end

outputs = [cols{:}];
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
