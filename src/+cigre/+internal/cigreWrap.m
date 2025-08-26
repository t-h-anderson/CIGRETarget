function [wrapper, c] = cigreWrap(model, nvp)
arguments
    model (1,1) string
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Ports"
    nvp.NameSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
end
% Generate the model reference
if nargout > 1
    [wrapper, c] = util.createBusExplodedWrapper(model, "BusAs", nvp.BusAs, "NameSuffix", nvp.NameSuffix, "VectorDataType", nvp.VectorDataType);
else
    wrapper = util.createBusExplodedWrapper(model, "BusAs", nvp.BusAs, "NameSuffix", nvp.NameSuffix, "VectorDataType", nvp.VectorDataType);
    c = [];
end

save_system(wrapper);

end

