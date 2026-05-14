function result = runDebugDLL(sessionZip, nvp)
% runDebugDLL Run a CIGRE DLL on a parallel worker for VS debugging.
%
%   result = cigre.internal.runDebugDLL("MyModel_session.zip")
%   [result, ~] = cigre.internal.runDebugDLL(bundle, "Compare", true)
%
% Unpacks a session bundle written by cigre.internal.buildDLLWithDebug,
% spawns a fresh parallel worker, prints the worker's OS PID so the user
% can attach Visual Studio (Debug > Attach to Process > MATLAB.exe with
% that PID), pauses for breakpoints, then parfeval's the DLL step loop.
% The worker isolation means a DLL crash kills only the worker, not the
% host MATLAB; the fresh parpool per call means a rebuilt DLL gets
% loaded from scratch each time so the "edit C, rebuild in VS, rerun"
% iteration loop works without re-running codegen.
%
% Inputs:
%   sessionZip - path to a .zip produced by buildDLLWithDebug.
%
% Returns:
%   result - timetable of DLL outputs, one row per simulation step.
%
% Name-Value Arguments:
%   Compare         - if true, diff the DLL output against the saved
%                     Simulink baseline (only meaningful when the bundle
%                     was built with Compare=true so a baseline exists).
%                     Default false: the debug workflow is about
%                     stepping through, not validating.
%   PauseBeforeRun  - if true (default), pause via keyboard after the
%                     worker is up so the user can attach VS. Set false
%                     for non-interactive reruns.
%   WaitTimeout     - parfeval wait timeout in seconds. Default 86400
%                     (one day) so the user can step through at human
%                     speed without parfeval declaring the worker stuck.
arguments
    sessionZip (1,1) string
    nvp.Compare (1,1) logical = false
    nvp.PauseBeforeRun (1,1) logical = true
    nvp.WaitTimeout (1,1) double = 86400
end

if ~isfile(sessionZip)
    error("CIGRE:runDebugDLL:SessionZipMissing", ...
        "Session bundle not found at %s", sessionZip);
end

% Extract into a fresh per-call temp folder. Each rerun gets its own
% copy of the DLL so a previously-loaded library on a dying worker
% doesn't leave file locks blocking the next rebuild.
extractDir = string(tempname);
mkdir(extractDir);
unzip(sessionZip, extractDir);

sessionMat = fullfile(extractDir, "debug_session.mat");
if ~isfile(sessionMat)
    error("CIGRE:runDebugDLL:SessionMatMissing", ...
        "debug_session.mat is missing from %s", sessionZip);
end
session = load(sessionMat);

% Sanity check the step count up front. A zero-row Outputs container
% would silently produce an empty result after parfeval (the DLL would
% be loaded and initialised but the step loop would not iterate),
% which is impossible to diagnose from the outside.
nSteps = size(session.Outputs, 1);
if nSteps == 0
    error("CIGRE:runDebugDLL:NoSteps", ...
        "Session bundle's Outputs timetable has 0 rows - the DLL would be loaded and initialised but no step would execute. Likely cause: the model's StopTime / FixedStep combination produced an empty time vector, or desc.Outputs was empty at bundle time.");
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
fprintf("########################################################\n");
fprintf("#  Worker PID:  %-8d                                  #\n", workerPid);
fprintf("#  Steps to run: %-6d                                  #\n", nSteps);
fprintf("#                                                      #\n");
fprintf("#  In Visual Studio:                                   #\n");
fprintf("#    Debug > Attach to Process                         #\n");
fprintf("#    select MATLAB.exe with PID %-8d                #\n", workerPid);
fprintf("#    set breakpoints in the C source                   #\n");
fprintf("########################################################\n");

if nvp.PauseBeforeRun
    fprintf("\n*** Attach VS, set breakpoints, then 'dbcont' to step into the DLL ***\n");
    keyboard %#ok<KEYBOARDFUN>
end

f = parfeval(p, @cigre.internal.runCigreDLL, 1, ...
    extractDir, session.DllName, session.Inputs, ...
    session.CIGREParameters, session.Outputs, session.TimeStep);
wait(f, "finished", nvp.WaitTimeout);

if p.NumWorkers == 0
    error("CIGRE:runDebugDLL:WorkerCrashed", ...
        "Parallel worker died (likely a DLL crash). Inspect the worker diary if any.");
end

result = f.fetchOutputs();
fprintf("DLL run complete (%d rows).\n", height(result));

if nvp.Compare
    if ~isfield(session, "Baseline") || isempty(session.Baseline)
        warning("CIGRE:runDebugDLL:NoBaseline", ...
            "Compare=true but the session bundle has no Baseline (rebuild with Compare=true on buildDLLWithDebug to populate it).");
        return
    end
    baselineTable = timetable2table(session.Baseline, 'ConvertRowTimes', false);
    baselineTable.Properties.VariableNames = result.Properties.VariableNames;
    baselineTable.Properties.VariableContinuity = [];

    passed = isequaln(result, baselineTable);
    if ~passed
        try
            import matlab.unittest.constraints.IsEqualTo
            import matlab.unittest.constraints.RelativeTolerance
            passed = IsEqualTo(baselineTable, "Within", RelativeTolerance(session.RelTol)) ...
                .satisfiedBy(result);
        catch
            passed = false;
        end
    end
    if passed
        fprintf("DLL output matches Simulink baseline within RelTol=%g.\n", session.RelTol);
    else
        fprintf("DLL output DIFFERS from Simulink baseline.\n");
        fprintf("  Load session.Baseline from %s to inspect.\n", sessionZip);
    end
end
end
