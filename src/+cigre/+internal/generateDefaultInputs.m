function inputs = generateDefaultInputs(desc, time)
% generateDefaultInputs Synthesise a stand-in input timetable for a model.
%
%   inputs = cigre.internal.generateDefaultInputs(desc, time)
%
% Returns a timetable matching the model's Inport interface, one variable
% per Inport, with each variable carrying a distinct constant signal
% (input k = k * ones) repeated across the supplied time vector and
% cast to the Inport's declared BaseType. Multi-dimensional Inports
% get the correct (t, m, n) shape so configureSimInputs and DataMap
% accept the result unchanged.
%
% Used as the no-input fallback for cigre.internal.buildDLLWithDebug,
% and as the test-class fallback inside
% test.system.tGenerateCigre.generateTestInputs when no InputData is
% saved on disk. The signal is intentionally simple - it doesn't
% exercise dynamics, but every wire carries a distinct, non-zero value
% so a wiring bug between the wrapper and the DLL surfaces on the
% first step rather than as silent zeros across the board.
%
% Inputs:
%   desc - cigre.description.ModelDescription returned by buildDLL.
%   time - column duration vector for the row times.
arguments
    desc
    time (:,1) duration
end

simInputs = desc.Inputs;
n = numel(simInputs);
if n == 0
    inputs = timetable.empty;
    return
end

cols = cell(1, n);
for i = 1:n
    spec = simInputs(i);
    d = spec.Dimensions;
    if isscalar(d)
        d = [d, 1];
    end
    template = ones(d);

    if spec.BaseType == "boolean"
        vals = (template ~= 0);
    else
        vals = cast(i * template, spec.BaseType);
    end

    % Replicate the per-step value across the time vector. For matrix
    % inputs the resulting array shape is t-by-m-by-n; permuting the
    % time axis to the front matches what configureSimInputs and
    % cigre.dll.DataMap.create expect.
    repl = repelem({vals}, numel(time), 1);
    repl = cat(3, repl{:});
    repl = permute(repl, [3, 1, 2]);

    % timetable/table constructors require their N-V pair names as
    % char vectors in legacy syntax, but the value can stay string.
    cols{i} = timetable(repl, 'RowTimes', time, 'VariableNames', "Var" + i);
end

inputs = [cols{:}];
end
