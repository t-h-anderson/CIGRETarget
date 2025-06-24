function bus = loadBus(model,name)

[~, cuo] = util.loadSystem(model); %#ok<ASGLU>

name = erase(name, "Bus:");

try
    bus = Simulink.data.evalinGlobal(model, name);
    bus.Description = name;
catch
    bus = [];
end

if numel(bus) ~= 1
    bus = Simulink.Bus.empty(1,0);
    return
end

end

