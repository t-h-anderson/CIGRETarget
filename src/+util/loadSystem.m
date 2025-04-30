function [mdlh, co] = loadSystem(model)

try
    if ~bdIsLoaded(model)

        mdlh = load_system(model);
        if nargout > 0
            co = onCleanup(@()close_system(model, 0));
        end
    else
        mdlh = get_param(model, "handle");
        co = [];
    end
catch me
    mdlh = [];
    co = [];
    disp("Failed to open model " + model + ". " + me.message);
end

end

