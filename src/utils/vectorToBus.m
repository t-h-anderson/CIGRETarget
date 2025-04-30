function [ports, idx, idxRange] = vectorToBus(signalInput, mdl, fromName, toName, creatorName, idx, terminate)
arguments
    signalInput
    mdl
    fromName
    toName
    creatorName
    idx = 0
    terminate (1,1) logical = false
end

busDef = loadBus(mdl, signalInput.BusObject);

if isempty(busDef)
    error("Bus definition not found")
end

busCreator = add_block("built-in/BusCreator", mdl + "/" + creatorName);

h = add_line(mdl, creatorName + "/1", toName);
set_param(h, "Name", signalInput.SignalName)

% Add the bus creator with an input for each signal
busElements = busDef.Elements;
set_param(busCreator,'Inputs',string(numel(busElements)));
ports = [];
idxRange = string.empty(1,0);

% output
for j = 1:numel(busElements)

    me = busElements(j);
    element = busDef.Elements(j);
    portName = fromName + "_" + busElements(j).Name;
    
    if ~contains(me.DataType, "Bus: ")
        % Add the in port with name in - originalName_busElementName

        ports(end+1) = add_block("simulink/Quick Insert/Signal Attributes/Cast", mdl + "/" + portName);
        
        if contains(element.DataType, "Enum:")
            % Need to convert input to integer before converting to enum
            ports(end) = add_block("simulink/Quick Insert/Signal Attributes/Cast", mdl + "/" + portName + "_toInt");
            set_param(ports(end), "OutDataTypeStr", "int32");

            add_line(mdl, portName + "_toInt/1", portName + "/" + 1);
        
        end

        if all(element.Dimensions ~= 1)
            reshape = add_block("simulink/Math Operations/Reshape", mdl + "/" + portName + "Reshape");
            add_line(mdl, portName + "/" + 1, portName + "Reshape/1");

            set_param(reshape, "OutputDimensionality", "Customize");
            set_param(reshape, "OutputDimensions", "[" + strjoin(string(element.Dimensions), ", ") + "]");
            
            here = portName + "Reshape";
            idxRange(end + 1) = (idx + 1) + ":" + (idx + sum(element.Dimensions));
            idx = idx + sum(element.Dimensions);
        else
            idx = idx + 1;
            here = portName;
            idxRange(end + 1) = string(idx);
        end
        
        l = add_line(mdl, here + "/1", creatorName + "/" + j);
        
        % Name is element
        Name = me.Name;
        set_param(l, "Name", Name);
    else
        elementCreatorName = creatorName + "_" + j;
        elementToName = creatorName + "/" + j;

        [p, idx, idxRanges] = vectorToBus(signalInput.Children(j), mdl, portName, elementToName, elementCreatorName, idx);
        ports = [ports, p];
        idxRange = [idxRange, idxRanges];
    end
    
end

% input
set_param(busCreator, "OutDataTypeStr", "Bus: " + signalInput.BusObject);

if terminate
    in = add_block("built-in/Inport", mdl + "/" + fromName);
    set_param(in, "OutDataTypeStr", "single");

    for i = 1:numel(ports)
        s = add_block("simulink/Signal Routing/Selector", mdl + "/" + portName + "select" , "MakeNameUnique", 'on');
        selector =  get_param(s, "Name");
        
        set_param(s,  "InputPortWidth", string(idx), "IndexParamArray", cellstr(idxRange(i)));
        
        inBlock = get_param(in, "Name");
        l = add_line(mdl, inBlock + "/1", selector + "/1");
        
        converter = get_param(ports(i), "Name");
        l = add_line(mdl, selector + "/1", converter + "/1");
    end
end

end