function result = runCigreDLL(dllDir, dllName, inputs, cigreParameters, outputs, timeStep)
% runCigreDLL Load a CIGRE DLL, step it through inputs, return outputs.
%
%   result = cigre.internal.runCigreDLL(dllDir, dllName, inputs, ...
%       cigreParameters, outputs, timeStep)
%
% Bare DLL invocation that handles load + initialise + step-row-by-row +
% unload. Designed to be called either in-process or via parfeval on a
% parallel worker (cigre.internal.runDebugDLL uses it the latter way so
% a DLL crash takes down only the worker, not the host MATLAB).
%
% Inputs:
%   dllDir          - folder containing <dllName>.dll. addpath'd inside
%                     so a parfeval worker that doesn't otherwise know
%                     about the unzipped session can resolve it.
%   dllName         - bare DLL name without extension or path.
%   inputs          - timetable of Inport values, one variable per
%                     wrapper-exploded leaf.
%   cigreParameters - struct array (.Name, .Value) of visible CIGRE
%                     parameters.
%   outputs         - timetable used purely as a shape allocator for
%                     cigre.dll.DataMap.create. The number of rows
%                     governs the step count; the column types govern
%                     the per-output byte layout. Pass a captured
%                     Simulink baseline or a synthesized
%                     zeros-of-the-right-shape timetable.
%   timeStep        - sample step, seconds.
arguments
    dllDir (1,1) string
    dllName (1,1) string
    inputs timetable
    cigreParameters (1,:) struct
    outputs
    timeStep (1,1) double
end

addpath(dllDir);

cigreDll = cigre.dll.CigreDLL(dllName);
cObj = cigreDll.load(); %#ok<NASGU>

inputs = retime(inputs, 'regular', 'nearest', 'TimeStep', seconds(timeStep));
inputsCell = table2cell(timetable2table(inputs));
inputsCell = inputsCell(:, 2:end);

instance = cigre.dll.InterfaceInstance(inputsCell, outputs, cigreParameters);
cigreDll.initialise(instance);

nSteps = size(outputs, 1);
if nSteps == 0
    % Without an explicit guard here, the DLL would be loaded and
    % initialised, the for loop below would simply not iterate, and
    % the caller would receive an empty result with no hint of why.
    % Surface the cause loudly so a misconfigured time vector /
    % outputs shape is obvious from the worker's stack trace.
    error("CIGRE:runCigreDLL:NoSteps", ...
        "outputs container has 0 rows - DLL was loaded and initialised but no step would execute. Check that the time vector / outputs shape were populated correctly at bundle time.");
end
fprintf("Stepping DLL for %d steps...\n", nSteps);
results = cell(1, nSteps);
for i = 1:nSteps
    instance.updateInputs(inputsCell, "Row", i);
    results{i} = cigreDll.step(instance);
end

result = cell2table(vertcat(results{:}));

instance.clear();
end
