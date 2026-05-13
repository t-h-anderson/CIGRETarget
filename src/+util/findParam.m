function [param,value] = findParam(mdl,param)
arguments
    mdl (1,1) string
    param (1,1) string
end

[~, co] = util.loadSystem(mdl); %#ok<ASGLU>

paramPath = strsplit(param, ".");
paramRoot = extractBefore(param + ".", ".");

try
    where = Simulink.findVars(mdl, "Name", paramRoot, "SearchMethod", "cached");
catch
    % SearchMethod="cached" is missing on older MATLAB releases.
    where = Simulink.findVars(mdl, "Name", paramRoot);
end

if isempty(where)
    error("Parameter " + param + " not found")
end

switch where.SourceType
    case "model workspace"
        mw = get_param(mdl, "ModelWorkspace");
        param = getVariable(mw, paramPath(1));
        value = param.Value;
    case "base workspace"
        param = evalin("base", param);
        value = param.Value;
    otherwise
        sldd = where.Source;
        try
            dd = Simulink.data.dictionary.open(sldd);
        catch
            error("Failed to open data dictionary " + sldd + " while searching for parameter " + param);
        end
        cuo = onCleanup(@() dd.close()); 
        s = dd.getSection("Design Data");
        param = s.getEntry(where.Name);
        value = param.getValue();
        if ~isnumeric(value)
            value = value.Value;
        end
end

% Dotted access into nested struct parameters (e.g. ctrl.pid.Kp).
for i = 2:numel(paramPath)
    try
        value = value.(paramPath(i));
    catch
        error("Parameter " + param + " not found in struct." + newline ...
            + "Closest match is at " + strjoin(paramPath(1:(i-1)), "."));
    end
end

end

