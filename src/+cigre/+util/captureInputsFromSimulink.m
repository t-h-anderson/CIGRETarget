function captureInputsFromSimulink(model, outFile, nvp)
% captureInputsFromSimulink Sim a model and dump its Inport signals.
%
%   cigre.util.captureInputsFromSimulink(model, outFile)
%
% Runs the model with its currently-configured external inputs and writes
% the time-stamped top-level Inport signals to outFile as a .mat file
% containing a single timetable variable named "input". The shape matches
% what loadData / cigre.internal.buildDLLWithDebug expects.
%
% The util enables signal logging on every top-level Inport for the
% duration of the sim and restores the prior LogSignals state afterwards
% (best-effort; failure to restore is non-fatal).
%
% Name-Value Arguments:
%   StopTime - sim stop time. Defaults to the model's saved StopTime.
%   TimeStep - fixed sample step. Defaults to the model's FixedStep.
%   Variable - name of the saved timetable variable in the .mat file
%              (default "input"; loaders take the first variable so the
%              name is mostly cosmetic).
arguments
    model (1,1) string
    outFile (1,1) string
    nvp.StopTime (1,1) double = NaN
    nvp.TimeStep (1,1) double = NaN
    nvp.Variable (1,1) string = "input"
end

[~, cMdl] = util.loadSystem(model); %#ok<ASGLU>

inports = find_system(model, "SearchDepth", 1, "BlockType", "Inport");
prevLogging = cell(numel(inports), 1);
for i = 1:numel(inports)
    prevLogging{i} = get_param(inports{i}, "DataLogging");
    % "DataLogging" is the Inport-block toggle for "Log signal data".
    % set_param accepts char only on R2020b, so wrap explicitly.
    try
        set_param(inports{i}, "DataLogging", 'on');
    catch
        % Some block configurations refuse the toggle (e.g. when an
        % Inport sits inside a referenced model). Leave it alone; the
        % logsout pull below will skip it.
    end
end
restore = onCleanup(@() restoreInportLogging(inports, prevLogging)); %#ok<NASGU>

simIn = Simulink.SimulationInput(model);
if ~isnan(nvp.StopTime)
    simIn = setModelParameter(simIn, "StopTime", string(nvp.StopTime));
end
if ~isnan(nvp.TimeStep)
    simIn = setModelParameter(simIn, "FixedStep", string(nvp.TimeStep));
end

% Make sure logsout is enabled for the run regardless of how the model
% was saved.
simIn = setModelParameter(simIn, "SignalLogging", "on");

results = sim(simIn);

logs = results.logsout;
if isempty(logs) || logs.numElements == 0
    error("CIGRE:captureInputsFromSimulink:NoLogs", ...
        "Simulation produced no logged Inport signals. Check that the model has top-level Inports and that signal logging is permitted on them.");
end

% Build a wide timetable: one variable per Inport signal, time axis taken
% from the first logged signal. Inports are matched by block name so
% downstream consumers can index by familiar names.
timetables = cell(1, logs.numElements);
for k = 1:logs.numElements
    el = logs{k};
    t = seconds(el.Values.Time);
    name = string(el.Name);
    if name == ""
        % Some R2020b configurations leave the element name blank;
        % fall back to a positional Var<k> so loadData-style consumers
        % still get a usable timetable.
        name = "Var" + k;
    end
    timetables{k} = timetable(t, el.Values.Data, 'VariableNames', name);
end

% synchronize the per-signal timetables onto a common time vector. Use
% nearest interpolation so we don't introduce intermediate samples beyond
% what each Inport actually produced.
combined = synchronize(timetables{:}, 'union', 'nearest');

savedVar.(nvp.Variable) = combined; %#ok<STRNU>
save(outFile, "-struct", "savedVar");

end


function restoreInportLogging(inports, prevLogging)
for i = 1:numel(inports)
    try
        set_param(inports{i}, "DataLogging", prevLogging{i});
    catch
        % best-effort restore; silently ignored
    end
end
end
