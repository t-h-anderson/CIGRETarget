function bus = loadBus(modelName, busName)
arguments
    modelName (1,1) string 
    busName (1,1) string
end

[~, cuo] = util.loadSystem(modelName); %#ok<ASGLU>

% Allow search for e.g. "Bus:myBus", "Bus: myBus", or "myBus"
busName = strtrim(erase(busName, "Bus:"));

try
    bus = Simulink.data.evalinGlobal(modelName, busName);
    bus.Description = busName;
catch
    bus = Simulink.Bus.empty(1,0);
end

if isempty(bus)
    bus = Simulink.Bus.empty(1,0);
end

end

