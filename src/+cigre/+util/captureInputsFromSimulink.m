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

% Signal logging lives on each Inport's output PORT, not on the Inport
% block itself - get_param(blockHandle, "DataLogging") errors with
% "Inport block does not have a parameter named 'DataLogging'". Walk
% PortHandles.Outport to reach the port that owns the toggle.
inports = find_system(model, "SearchDepth", 1, "BlockType", "Inport");
inportPorts = zeros(numel(inports), 1);
prevLogging = strings(numel(inports), 1);
for i = 1:numel(inports)
    ph = get_param(inports{i}, "PortHandles");
    inportPorts(i) = ph.Outport(1);
    prevLogging(i) = string(get_param(inportPorts(i), "DataLogging"));
    try
        set_param(inportPorts(i), "DataLogging", "on");
    catch
        % Some configurations (e.g. an Inport feeding directly into a
        % referenced model with a fixed signal-logging policy) refuse
        % the toggle. Leave the port alone; if the signal still isn't
        % logged it will simply be absent from logsout and we'll error
        % below.
    end
end
restore = onCleanup(@() restoreInportLogging(inportPorts, prevLogging)); %#ok<NASGU>

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


function restoreInportLogging(inportPorts, prevLogging)
% Best-effort restore of each port's pre-call DataLogging state. Errors
% (e.g. the port no longer exists because the model was closed) are
% swallowed: this is a cleanup hook on an onCleanup, so the worst case
% is we leave one Inport with signal logging stuck on, which is
% harmless.
for i = 1:numel(inportPorts)
    try
        set_param(inportPorts(i), "DataLogging", char(prevLogging(i)));
    catch
    end
end
end
