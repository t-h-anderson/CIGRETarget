function baseline = extractData(results)


if verLessThan("MATLAB", "9.9")
     
    try
        y = results.yout;
    catch
        % TODO: This should probably just be an empty timetable
        y = results.logsout;
    end
    
    tt = {};
    for i = 1:(y.numElements)
        t = seconds(y{i}.Values.Time);
        yvals = y{i}.Values.Data;
        
        % Ensure that first dimension is time. Needed for matrix IO
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
    baseline = fillmissing(baseline, "previous");
        
else
    
    try
        baseline = results.yout.extractTimetable();
    catch
        % TODO: This should probably just be an empty timetable
        baseline = results.logsout.extractTimetable();
    end
    
end

baseline = fillmissing(baseline, "previous");

end

