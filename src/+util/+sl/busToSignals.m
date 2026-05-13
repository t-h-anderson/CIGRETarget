function busToSignals(busOutput, mdl, fromName, toName, selectorName)
arguments
    busOutput (1,1)
    mdl (1,1) string
    fromName (1,1) string
    toName (1,1) string
    selectorName (1,1) string
end

b = add_block("built-in/BusSelector", mdl + "/" + selectorName);

busElementOutput = busOutput.Elements;
signals = string({busElementOutput.Name});
add_line(mdl, fromName, selectorName + "/1");

set_param(b, "OutputSignals", strjoin(signals, ","));

for j = 1:numel(busElementOutput)

    portName = toName + "_" + busElementOutput(j).Name;

    children = util.sl.loadBus(mdl, busElementOutput(j).DataType);
    if isempty(children)

        nextBlock = selectorName + "/" + j;

        if startsWith(busElementOutput(j).DataType, "Enum: ")
            % The CIGRE ABI exposes enums as int32; cast before the
            % wrapper outport so the external interface stays integral.
            c = add_block("simulink/Quick Insert/Signal Attributes/Cast", mdl + "/Convert" + portName);
            set_param(c, "OutDataTypeStr", "int32");
            add_line(mdl, selectorName + "/" + j, "Convert" + portName + "/1");
            nextBlock = "Convert" + portName + "/1";
        end

        add_block("built-in/Outport", mdl + "/" + portName);
        add_line(mdl, nextBlock, portName + "/1");
    else
        util.sl.busToSignals(children, mdl, selectorName + "/" + j, portName, selectorName + "_" + j)
    end
end

end