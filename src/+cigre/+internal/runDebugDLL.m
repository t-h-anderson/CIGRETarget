function result = runDebugDLL(dllPath, nvp)
% runDebugDLL Run a CIGRE DLL on a parallel worker for VS debugging.
%
%   result = cigre.internal.runDebugDLL(dllPath)
%   result = cigre.internal.runDebugDLL(dllPath, ...
%       "Inputs", inputsTimetable, "Parameters", cigreParams)
%
% Spawns a fresh parallel worker, prints the worker's OS PID so the
% user can attach Visual Studio (Debug > Attach to Process >
% MATLAB.exe with that PID), pauses for breakpoints, then parfeval's
% cigre.internal.runCigreDLL. Worker isolation means a DLL crash
% kills only the worker, not the host MATLAB; the fresh parpool per
% call means a rebuilt DLL is loaded from scratch each time so the
% "edit C, MSBuild again, rerun" iteration loop works without any
% MATLAB-side state to clean up.
%
% Everything other than the DLL is optional: the function introspects
% the DLL header (Model_GetInfo, via cigre.importer.ModelInfo) for the
% sample time and the input / output / parameter port layout, so it
% does not need the ModelDescription that produced the DLL. The DLL
% path alone is enough for a smoke run; supply Inputs / Parameters to
% drive specific data through.
%
% Inputs:
%   dllPath - absolute path to a CIGRE DLL (e.g. the second output of
%             cigre.buildDLL(..., "Debug", true)).
%
% Name-Value Arguments:
%   Inputs         - timetable of Inport values, retimed onto the
%                    DLL's sample grid. Default: a synthetic
%                    constant-per-port stand-in NumSteps rows long.
%   Parameters     - (1,:) struct array (.Name, .Value) of CIGRE
%                    parameter values. Default: each DLL parameter at
%                    its declared DefaultValue.
%   NumSteps       - step count for the synthetic default Inputs
%                    (ignored when Inputs is supplied). Default 100.
%   PauseBeforeRun - if true (default), pause via keyboard after the
%                    worker is up so the user can attach VS. Set false
%                    for non-interactive reruns.
%   WaitTimeout    - parfeval wait timeout in seconds. Default 86400
%                    (one day) so the user can step through at human
%                    speed without parfeval declaring the worker stuck.
arguments
    dllPath (1,1) string
    nvp.Inputs timetable = timetable.empty
    nvp.Parameters struct = struct("Name", {}, "Value", {})
    nvp.NumSteps (1,1) double {mustBePositive} = 100
    nvp.PauseBeforeRun (1,1) logical = true
    nvp.WaitTimeout (1,1) double = 86400
end

if ~isfile(dllPath)
    error("CIGRE:runDebugDLL:DLLMissing", ...
        "DLL not found at %s", dllPath);
end

[dllDir, dllBase, ~] = fileparts(dllPath);
dllDir = string(dllDir);
dllName = string(dllBase);

% Read the DLL header for the sample time and port layout. This is
% what lets runDebugDLL stay light - the DLL describes itself.
info = cigre.importer.ModelInfo.fromDLL(dllPath);
timeStep = info.SampleTime;
if timeStep <= 0
    error("CIGRE:runDebugDLL:BadSampleTime", ...
        "DLL reports a non-positive FixedStepBaseSampleTime (%g).", timeStep);
end

% Resolve inputs: the supplied timetable retimed onto the DLL's sample
% grid, or a synthetic constant-per-port stand-in NumSteps rows long.
if isempty(nvp.Inputs)
    nSteps = nvp.NumSteps;
    inputs = dllSignalTimetable(info.Inputs, stepTimes(nSteps, timeStep), "index");
else
    inputs = retime(nvp.Inputs, 'regular', 'nearest', 'TimeStep', seconds(timeStep));
    nSteps = height(inputs);
end
if nSteps == 0
    error("CIGRE:runDebugDLL:NoSteps", ...
        "Resolved a zero-length input - nothing to step.");
end

% The outputs container is purely a shape allocator for
% cigre.dll.DataMap.create; a zeros timetable from the DLL's declared
% output ports gives it the right per-port type and width, and the
% row count drives the step loop in runCigreDLL.
outputs = dllSignalTimetable(info.Outputs, stepTimes(nSteps, timeStep), "zeros");

% Resolve parameters: the supplied override, or each DLL parameter at
% its declared DefaultValue.
if isempty(nvp.Parameters)
    cigreParameters = defaultParameters(info.Parameters);
else
    cigreParameters = nvp.Parameters;
end

% Tear down any existing pool so the worker reloads the (possibly
% rebuilt) DLL from scratch on each call. backgroundPool runs
% in-process and cannot host a loaded DLL safely, so we force a
% Processes pool with one worker.
delete(gcp("nocreate"));
p = parpool(1);
state = warning("query", "parallel:cluster:LocalWorkerCrash").state;
warning("off", "parallel:cluster:LocalWorkerCrash");
cleanWarn = onCleanup(@() warning(state, "parallel:cluster:LocalWorkerCrash")); %#ok<NASGU>

% Surface the worker's OS PID so the user can attach VS to it before
% the DLL is loaded. parfeval(@()feature("getpid")) on the worker
% returns the worker's PID, not the host's.
fPid = parfeval(p, @() feature("getpid"), 1);
wait(fPid, "finished", 30);
workerPid = fPid.fetchOutputs();

fprintf("\n");
fprintf("========================================================\n");
fprintf("  Worker PID for VS Attach: %d\n", workerPid);
fprintf("  Steps to run: %d\n", nSteps);
fprintf("\n");
fprintf("  In Visual Studio:\n");
fprintf("    Debug > Attach to Process\n");
fprintf("    select MATLAB.exe with PID %d\n", workerPid);
fprintf("    set breakpoints in the C source\n");
fprintf("========================================================\n");

if nvp.PauseBeforeRun
    fprintf("\n*** Attach VS, set breakpoints, then 'dbcont' to step into the DLL ***\n");
    keyboard %#ok<KEYBOARDFUN>
end

f = parfeval(p, @cigre.internal.runCigreDLL, 1, ...
    dllDir, dllName, inputs, cigreParameters, outputs, timeStep);
wait(f, "finished", nvp.WaitTimeout);

if p.NumWorkers == 0
    error("CIGRE:runDebugDLL:WorkerCrashed", ...
        "Parallel worker died (likely a DLL crash). Inspect the worker diary if any.");
end

result = f.fetchOutputs();
fprintf("DLL run complete (%d rows).\n", height(result));
end


function t = stepTimes(nSteps, timeStep)
% Column duration vector for an nSteps run on the DLL's sample grid.
t = seconds((0:nSteps-1)' * timeStep);
end


function tt = dllSignalTimetable(signals, time, fill)
% Build a timetable matching a ModelInfo signal-port array. Each port
% becomes one variable, width signals(k).Width, type
% cigreTypeToSimulink(signals(k).DataType). The CIGRE ABI carries
% every port as a flat vector, so there are no matrix dimensions to
% reconstruct. fill "index" gives port k the constant k (a distinct
% non-zero value per wire); "zeros" gives an all-zero output-shape
% allocator the DLL overwrites.
arguments
    signals struct
    time (:,1) duration
    fill (1,1) string {mustBeMember(fill, ["index", "zeros"])}
end

n = numel(signals);
if n == 0
    tt = timetable.empty;
    return
end

nSteps = numel(time);
cols = cell(1, n);
for k = 1:n
    matlabType = cigre.importer.ModelInfo.cigreTypeToSimulink(signals(k).DataType);
    width = double(signals(k).Width);
    if fill == "index"
        vals = cast(k, matlabType) * ones(nSteps, width, matlabType);
    else
        vals = zeros(nSteps, width, matlabType);
    end
    cols{k} = timetable(vals, 'RowTimes', time, 'VariableNames', "Var" + k);
end
tt = [cols{:}];
end


function params = defaultParameters(infoParams)
% Each DLL parameter at its declared DefaultValue, cast to the
% parameter's CIGRE data type.
arguments
    infoParams struct
end

params = struct("Name", {}, "Value", {});
for k = 1:numel(infoParams)
    pk = infoParams(k);
    matlabType = cigre.importer.ModelInfo.cigreTypeToSimulink(pk.DataType);
    params(k) = struct("Name", string(pk.Name), ...
        "Value", cast(pk.DefaultValue, matlabType)); %#ok<AGROW>
end
end
