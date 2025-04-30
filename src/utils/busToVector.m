function sigs = busToVector(busOutput, mdl, fromName, toName, selectorName, terminate)
arguments
    busOutput
    mdl
    fromName
    toName
    selectorName
    terminate (1,1) logical = false
end
sigs = [];

busDef = loadBus(mdl, busOutput.Description);

busElementOutput = busOutput.Elements;
b = add_block("built-in/BusSelector", mdl + "/" + selectorName);

signals = string({busOutput.Elements.Name});
add_line(mdl, fromName, selectorName + "/1");

set_param(b, "OutputSignals", strjoin(signals, ","));

for j = 1:numel(busElementOutput)
    me = busElementOutput(j);
    element = busDef.Elements(j);

    portName = toName + "_" + me.Name;

    if ~contains(me.DataType, "Bus: ")
        sigs(end+1) = add_block("simulink/Quick Insert/Signal Attributes/Cast To Single", mdl + "/" + portName);
        add_line(mdl, selectorName + "/" + j, portName + "/1");
        
        if all(element.Dimensions ~= 1)
            sigs(end) = add_block("simulink/Math Operations/Reshape", mdl + "/" + portName + "Reshape");
            add_line(mdl, portName + "/" + 1, portName + "Reshape/1");
        end
        
    else

        bus = loadBus(mdl, me.DataType);

        s = busToVector(bus, mdl, selectorName + "/" + j, portName, selectorName + "_" + j);
        sigs = [sigs, s];
    end
end

s = add_block("simulink/Signal Routing/Vector Concatenate", mdl + "/ToVector" , "MakeNameUnique", 'on');
vCast = get_param(s, "Name");

set_param(mdl + "/" + vCast, "NumInputs", string(numel(sigs))); % Ensure we have enough ports
for i = 1:numel(sigs)
    block = get_param(sigs(i), "Name");
    add_line(mdl, block + "/1", vCast + "/" + i);
end

if ~terminate
    sigs = s;
else
    b = add_block("built-in/Outport", mdl + "/" + toName);
    s = get_param(s, "Name");
    add_line(mdl, s + "/" + 1, toName + "/1");
    sigs = [];
end

end

function val = selectBusName(signal)

if iscell(signal)
    val = string(signal{1});
else
    val = string(signal);
end
end