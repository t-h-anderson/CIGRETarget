function value = findParam(mdl,param)
arguments
    mdl (1,1) string
    param (1,1) string
end

[~, co] = util.loadSystem(mdl);

% Probably should be missing, but not supported for e.g. integers
failedValue = 0;

paramPath = strsplit(param, ".");
paramRoot = extractBefore(param + ".", ".");

try
    where = Simulink.findVars(mdl, "Name", paramRoot, "SearchMethod", "cached");
catch
    where = Simulink.findVars(mdl, "Name", paramRoot);
end

if isempty(where)
    error("Parameter " + param + " not found")
end

switch where.SourceType
    case "model workspace"
        mw = get_param(mdl, "ModelWorkspace");
        value = getVariable(mw, paramPath(1)).Value;
    case "base workspace"
        value = failedValue; % Not supported
    otherwise
        % Try in a data dictionary
        sldd = where.Source;
        try
            dd = Simulink.data.dictionary.open(sldd);
        catch
            error("Failed to open data dictionary " + sldd + " while searching for parameter " + param);
        end
        cuo = onCleanup(@() dd.close()); 
        s = dd.getSection("Design Data");
        p = s.getEntry(where.Name);
        value = p.getValue();
        if ~isnumeric(value)
            value = value.Value;
        end
end

% Access parameters in a struct
for i = 2:numel(paramPath)
    try
        value = value.(paramPath(i));
    catch
        error("Parameter " + param + " not found in struct." + newline ...
            + "Closest match is at " + strjoin(paramPath(1:(i-1)), "."));
    end
end

end

