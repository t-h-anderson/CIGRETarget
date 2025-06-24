function [wrapperName, cWrap] = createBusExplodedWrapper(model, nvp)
arguments
    model (1,1) string
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Ports"
    nvp.NameSuffix (1,1) string = "_wrap"
end

% Ensure the model is loaded, if not, close after we leave the explode
% function
[mdlh, cMdl] = util.loadSystem(model); %#ok<ASGLU>

% Ensure that a fresh wrapper can be created.
wrapperName = model + nvp.NameSuffix;
bdclose(wrapperName);
if exist(wrapperName, 'file')
    disp("Deleting existing wrapper: " + wrapperName)
    w = which(wrapperName);
    if ~isempty(w)
        delete(w);
    end
end

% Create and load the wrapper
new_system(wrapperName);
if nargout > 1
    [~, cWrap] = util.loadSystem(wrapperName);
else
    util.loadSystem(wrapperName);
    cWrap = [];
end

% Copt the config set from the model to the wrapper
config = getActiveConfigSet(model);
if ~isa(config, 'Simulink.ConfigSet')
    % If the config is a reference, break the link so we can customise
    config = config.getRefConfigSet;
end
newConfig = copy(config);
newConfig.Name = "CopiedConfig";
attachConfigSet(wrapperName, newConfig);
setActiveConfigSet(wrapperName, newConfig.Name);

% Update the coder mappings
%cm = coder.mapping.api.get(wrapperName,'EmbeddedCoderC');
cm = coder.mapping.utils.create(wrapperName);
if ~verLessThan("MATLAB", "9.9")
    cm.setDataDefault("ModelParameterArguments", "StorageClass", "MultiInstance");
end

% Copy the data dictionaries
dd = get_param(model, "DataDictionary");
set_param(wrapperName, "DataDictionary", dd);

% Add a model reference back to the model
ref = wrapperName + "/mdl";
mdlRef = add_block("built-in/ModelReference", ref);
set_param(mdlRef, "ModelNameDialog", model) % Link to the original model
set_param(mdlRef, "SimulationMode", "Normal") % Ensure we are not in rapid accelerator mode

% Update the model reference to set the model parameters
p = get_param(mdlRef, "InstanceParameters");
for i = 1:numel(p)
    p(i).Value = '0';
    p(i).Argument = true;
end
set_param(mdlRef, "InstanceParameters", p);

%% Input
% Find in the inports on the top level model. Work backwards from the
% reference to explode buses
inhs = find_system(mdlh, "SearchDepth", 1, "BlockType", "Inport");

for i = 1:numel(inhs)
    inh = inhs(i);

    name = get_param(inh, "Name");

    % Determine if the port is a non-virtual bus
    inTypes = string(get_param(inh, "OutDataTypeStr"));
    isBus = contains(inTypes, "Bus:");
    isEnum = contains(inTypes, "Enum:");

    % Port is a bus, so need to be exploded
    inOutSignals = get_param(inh, "PortHandles");
    inputSignals = get_param(inOutSignals.Outport, "SignalHierarchy");

    if isBus
        
        if isempty(inputSignals.BusObject)
            error(inTypes + " definition not found")
        end
        
        % define what needs creating - a bus creator that will be linked to
        % the first port of the reference model
        creatorName = "creator" + i;
        fromName = name;
        toName = "mdl/" + i;

        switch nvp.BusAs
            case "Ports"
                % Add a bus creator (recursive)
                signalsToBus(inputSignals, wrapperName, fromName, toName, creatorName);
            otherwise
                vectorToBus(inputSignals, wrapperName, fromName, toName, creatorName, 0, true);
        end
    elseif isEnum

        name = cleanName(name);
        
        % Need to convert input to integer before converting to enum
        c = add_block("simulink/Quick Insert/Signal Attributes/Cast", wrapperName + "/Convert" + name);
        set_param(c, "OutDataTypeStr", inTypes);
        l = add_line(wrapperName, "Convert" + name + "/1", "mdl/" + i);

        in = add_block("built-in/Inport", wrapperName + "/" + name);
        set_param(in, "OutDataTypeStr", "int32");
        add_line(wrapperName, name + "/1", "Convert" + name + "/" + 1);

        signalName = inputSignals.SignalName; 
        set_param(l, "Name", signalName);

    else
        % Add the inport and connect it up
        name = cleanName(name);
        add_block("built-in/Inport", wrapperName + "/" + name);
        l = add_line(wrapperName, name + "/1", "mdl/" + i);

        signalName = inputSignals.SignalName; 
        set_param(l, "Name", signalName);
    end

end


% Output
outh = find_system(mdlh, "SearchDepth", 1, "BlockType", "Outport");
for i = 1:numel(outh)

    outTypes = string(get_param(outh(i), "OutDataTypeStr"));

    isBus = contains(outTypes, "Bus:");
    isEnum = contains(outTypes, "Enum:");

    name = get_param(outh(i), "Name");

    if isBus

        bus = loadBus(model, outTypes);

        selectorName = "selector" + i;
        toName = name;
        fromName = "mdl/" + i;
        
        switch nvp.BusAs
            case "Ports"
                % Add a bus creator (recursive)
                busToSignals(bus, wrapperName, fromName, toName, selectorName);
            otherwise
                busToVector(bus, wrapperName, fromName, toName, selectorName, true);
        end

    elseif isEnum

        name = cleanName(name);
        
        % Need to convert input to integer before converting to enum
        c = add_block("simulink/Quick Insert/Signal Attributes/Cast", wrapperName + "/Convert" + name);
        set_param(c, "OutDataTypeStr", "int32");
        l = add_line(wrapperName, "mdl/" + i, "Convert" + name + "/1");

        in = add_block("built-in/Outport", wrapperName + "/" + name);
        set_param(in, "OutDataTypeStr", "int32");
        add_line(wrapperName, "Convert" + name + "/" + 1, name + "/1");

        signalName = inputSignals.SignalName; 
        set_param(l, "Name", signalName);

    else

        outInputSignals = get_param(outh(i), "PortHandles");
        outputSignals = get_param(outInputSignals.Inport, "SignalHierarchy");

        name = cleanName(name);
        add_block("built-in/Outport", wrapperName + "/" + name);
        l = add_line(wrapperName, "mdl/" + i, name + "/1");

        signalName = outputSignals.SignalName; 
        set_param(l, "Name", signalName);        
    end
end

Simulink.BlockDiagram.arrangeSystem(wrapperName);


% Set the parameters in the wrapper
ip = get_param(mdlRef, "InstanceParameters");

if ~isempty(ip)
    
    mws = get_param(model, "ModelWorkspace");
    p = mws.whos;
    wws = get_param(wrapperName, "ModelWorkspace");
    
    ipNames = string({ip.Name});
    for i= 1:numel(p)
        name = p(i).name;
        var = mws.getVariable(name);
        assignin(wws, name, var);
        
        idx = (ipNames == name);
        if any(idx)
            ip(idx).Value = char(util.valToString(var.Value));
        end
    end

    ipNew = arrayfun(@(x) renameStructField(x, {"Path"}, {"FullPath"}), ip);
    set_param(mdlRef, "InstanceParameters", ipNew);
end

end

function name = cleanName(name)

name = strrep(name, "/", "//"); % Allow slashes in the name

end
