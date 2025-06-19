function busToSignals(busOutput, mdl, fromName, toName, selectorName)

b = add_block("built-in/BusSelector", mdl + "/" + selectorName);

busElementOutput = busOutput.Elements;
signals = string({busElementOutput.Name});
add_line(mdl, fromName, selectorName + "/1");

set_param(b, "OutputSignals", strjoin(signals, ","));

for j = 1:numel(busElementOutput)

    portName = toName + "_" + busElementOutput(j).Name;

    children = loadBus(mdl, busElementOutput(j).DataType);
    if isempty(children)

        nextBlock = selectorName + "/" + j;

        if startsWith(busElementOutput(j).DataType, "Enum: ")
             
            % Need to convert enums to integers
            c = add_block("simulink/Quick Insert/Signal Attributes/Cast", mdl + "/Convert" + portName);
            set_param(c, "OutDataTypeStr", "int32");
            add_line(mdl, selectorName + "/" + j, "Convert" + portName + "/1");
            nextBlock = "Convert" + portName + "/1";
        end

        add_block("built-in/Outport", mdl + "/" + portName);
        add_line(mdl, nextBlock , portName + "/1");
    else
        busToSignals(children, mdl, selectorName + "/" + j, portName, selectorName + "_" + j)
    end
end

end