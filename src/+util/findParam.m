function value = findParam(mdl,name)
failedValue = 0;

where = Simulink.findVars(mdl, "Name", name, "SearchMethod", "cached");

switch where.SourceType
    case "model workspace"
        mw = get_param(mdl, "ModelWorkspace");
        value = getVariable(mw, name).Value;
    case "base workspace"
        value = failedValue; % Not supported
    otherwise
        % Data dict?
        dd = Simulink.data.dictionary.open(where.Source);
        cuo = onCleanup(@() dd.close()); 
        s = dd.getSection("Design Data");
        p = s.getEntry(where.Name);
        value = p.getValue();
        if ~isnumeric(value)
            value = value.Value;
        end
end

% Fail early if we can't convert it to a double
double(value);

end

