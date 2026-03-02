function [mdlh, co] = loadSystem(model)
arguments
    model (1,1) string
end

if ~bdIsLoaded(model)

    mdlh = load_system(model);
    if nargout > 0
        co = onCleanup(@()close_system(model, 0));
    end
else
    mdlh = get_param(model, "handle");
    co = [];
end

end
