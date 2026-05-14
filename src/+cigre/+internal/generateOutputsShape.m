function outputs = generateOutputsShape(desc, time)
% generateOutputsShape Synthesise a zeros timetable matching wrapper Outports.
%
%   outputs = cigre.internal.generateOutputsShape(desc, time)
%
% Returns a timetable whose variables match the wrapper's exploded
% Outport interface (one variable per Outport leaf, sized to the
% Outport's Dimensions and typed to its BaseType, repeated across the
% supplied time vector). Used as the shape allocator for
% cigre.dll.DataMap.create / cigre.dll.InterfaceInstance when no
% Simulink baseline run is being captured (for example by
% cigre.internal.runDebugDLL when its caller doesn't care about
% diffing the DLL output).
%
% Mirrors cigre.internal.generateDefaultInputs but populates with
% zeros (false for boolean BaseTypes) instead of constants.
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

    % Replicate the per-step value across the time vector. For matrix
    % outputs the resulting array shape is t-by-m-by-n; permuting the
    % time axis to the front matches what cigre.dll.DataMap.create
    % expects.
    repl = repelem({template}, numel(time), 1);
    repl = cat(3, repl{:});
    repl = permute(repl, [3, 1, 2]);

    cols{i} = timetable(repl, 'RowTimes', time, 'VariableNames', "Var" + i);
end

outputs = [cols{:}];
end
