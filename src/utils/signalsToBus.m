function signalsToBus(signalInput, mdl, fromName, toName, creatorName)

% Add the bus creator with an input for each signal

busDef = loadBus(mdl, signalInput.BusObject);

busElements = busDef.Elements;
busCreator = add_block("built-in/BusCreator", mdl + "/" + creatorName);
set_param(busCreator, "Inputs", string(numel(busElements)));
set_param(busCreator, "OutDataTypeStr", "Bus: " + signalInput.BusObject);

for j = 1:numel(busElements)

    portName = fromName + "_" + busElements(j).Name;

    if ~contains(busElements(j).DataType, "Bus:")

    % Add the in port with name in - originalName_busElementName
        in = add_block("built-in/Inport", mdl + "/" + portName);

        nextBlock = creatorName + "/" + j;  

        if startsWith(busElements(j).DataType, "Enum: ")

            % Need to convert enums to integers
            c = add_block("simulink/Quick Insert/Signal Attributes/Cast", mdl + "/Convert" + portName);
            set_param(c, "OutDataTypeStr", busElements(j).DataType);
            l = add_line(mdl, "Convert" + portName + "/1", creatorName + "/" + j);
            
            signalName = busElements(j).Name; 
            set_param(l, "Name", signalName);

            nextBlock = "Convert" + portName + "/1";

            set_param(in, "OutDataTypeStr", "int32");
        end

        l = add_line(mdl, portName + "/1", nextBlock);

        % Name is element
        signalName = busElements(j).Name; 
        set_param(l, "Name", signalName);
    else
        elementCreatorName = creatorName + "_" + j;
        elementToName = creatorName + "/" + j;
        signalsToBus(signalInput.Children(j), mdl, portName, elementToName, elementCreatorName)
    end
end

h = add_line(mdl, creatorName + "/1", toName);
set_param(h, "Name", signalInput.SignalName)
end