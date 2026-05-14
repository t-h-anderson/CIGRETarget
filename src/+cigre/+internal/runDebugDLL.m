function result = runDebugDLL(dllPath, inputs, cigreParameters, outputs, timeStep, nvp)
% runDebugDLL Run a CIGRE DLL on a parallel worker for VS debugging.
%
%   result = cigre.internal.runDebugDLL( ...
%       dllPath, inputs, cigreParameters, outputs, timeStep)
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
% This is the debug-loop side of the pivot away from a single
% orchestrator: cigre.buildDLL(..., "Debug", true) produces the DLL
% (and is composable with cigre.importDLL for Simulink); this
% function runs it for the MATLAB harness case.
%
% Inputs:
%   dllPath          - absolute path to the debug DLL produced by
%                      cigre.buildDLL(..., "Debug", true).
%   inputs           - timetable of Inport values; cigre.dll.DataMap
%                      reads the per-column type and dimensions from it.
%   cigreParameters  - (1,:) struct array (.Name, .Value) of visible
%                      CIGRE parameter values.
%   outputs          - timetable used as a shape allocator for
%                      cigre.dll.DataMap.create. Pass either a captured
%                      Simulink baseline (if you want a reference to
%                      diff against later) or
%                      cigre.internal.generateOutputsShape(desc, time).
%   timeStep         - sample step, seconds.
%
% Name-Value Arguments:
%   PauseBeforeRun  - if true (default), pause via keyboard after the
%                     worker is up so the user can attach VS. Set false
%                     for non-interactive reruns.
%   WaitTimeout     - parfeval wait timeout in seconds. Default 86400
%                     (one day) so the user can step through at human
%                     speed without parfeval declaring the worker stuck.
arguments
    dllPath (1,1) string
    inputs timetable
    cigreParameters (1,:) struct
    outputs
    timeStep (1,1) double
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

% Sanity-check the step count before any parallel-pool work; a zero-row
% outputs container would silently make the parfeval body load and
% initialise the DLL but never call Model_Outputs, which is impossible
% to diagnose from the outside.
nSteps = size(outputs, 1);
if nSteps == 0
    error("CIGRE:runDebugDLL:NoSteps", ...
        "outputs timetable has 0 rows - the DLL would be loaded and initialised but no step would execute. Check that the time vector / outputs shape were populated correctly upstream.");
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
