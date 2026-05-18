function baseline = extractData(results, opts)
arguments
    results (1,1)
    opts.LegacyMatlab (1,1) logical = compat.legacyMatlab()
end

if opts.LegacyMatlab

    try
        y = results.yout;
    catch
        y = results.logsout;
    end

    tt = {};
    for i = 1:(y.numElements)
        t = seconds(y{i}.Values.Time);
        yvals = y{i}.Values.Data;

        % Permute so that time is the leading dimension, required for
        % matrix-valued signals where the time axis may be trailing.
        tidx = find(size(yvals) == numel(t), 1, "last");
        idx = 1:numel(size(yvals));
        idx(tidx) = [];
        idx = [tidx, idx];
        yvals = permute(yvals, idx);

        thisName = string(y{i}.BlockPath.convertToCell);
        [~, thisName] = fileparts(thisName);

        tt{i} = timetable(t, yvals, 'VariableNames', thisName);
    end

    baseline = synchronize(tt{:}, 'union', 'previous');
    baseline = fillmissing(baseline, 'previous');

else

    try
        baseline = results.yout.extractTimetable('OutputFormat', 'cell-by-signal');
    catch
        baseline = results.logsout.extractTimetable('OutputFormat', 'cell-by-signal');
    end

end

% Retime to the output timestep (results.tout) so each signal lines up
% on a uniform grid regardless of its native sample rate.
baseline = retime(baseline{:}, seconds(results.tout));

end
