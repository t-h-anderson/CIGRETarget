function [wrapperName, cWrap] = createBusExplodedWrapper(model, nvp)
arguments
    model (1,1) string
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Ports"
    nvp.NameSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
end

[mdlh, cMdl] = util.loadSystem(model); %#ok<ASGLU>

wrapperName = model + nvp.NameSuffix;
bdclose(wrapperName);
if exist(wrapperName, "file")
    disp("Deleting existing wrapper: " + wrapperName)
    w = which(wrapperName);
    if ~isempty(w)
        delete(w);
    end
end

new_system(wrapperName);
if nargout > 1
    [~, cWrap] = util.loadSystem(wrapperName);
else
    util.loadSystem(wrapperName);
    cWrap = [];
end

config = getActiveConfigSet(model);
if ~isa(config, "Simulink.ConfigSet")
    % Config is a reference set; break the link so the wrapper can hold
    % its own copy without mutating the original.
    config = config.getRefConfigSet;
end
newConfig = copy(config);
newConfig.Name = "CopiedConfig";
attachConfigSet(wrapperName, newConfig);
setActiveConfigSet(wrapperName, newConfig.Name);

cm = coder.mapping.utils.create(wrapperName);
if ~verLessThan("MATLAB", "9.9")
    try
        cm.setDataDefault("ModelParameterArguments", "StorageClass", "MultiInstance");
    catch
        % "MultiInstance" was added to the coder.mapping storage-class
        % vocabulary after R2020b (R2020b only accepts "Default"). On
        % releases where it isn't recognised, fall through and let the
        % default storage class stand - codegen still succeeds, but
        % model arguments behave as plain global data.
    end
end

dd = get_param(model, "DataDictionary");
set_param(wrapperName, "DataDictionary", dd);

ref = wrapperName + "/mdl";
mdlRef = add_block("built-in/ModelReference", ref);
set_param(mdlRef, "ModelNameDialog", model)
% Normal sim mode keeps tunable parameters live; rapid accelerator would
% freeze them at compile.
set_param(mdlRef, "SimulationMode", "Normal")

p = get_param(mdlRef, "InstanceParameters");
for i = 1:numel(p)
    % Simulink stores InstanceParameters.Value as char; a placeholder
    % literal here is overwritten further down with the actual default.
    p(i).Value = '0';
    p(i).Argument = true;
end
set_param(mdlRef, "InstanceParameters", p);

%% Input
% Explode each top-level Inport, replacing buses with either per-signal
% ports or a single concatenated vector port. Working from the model
% reference outward keeps the original block ordering on the wrapper.
inhs = find_system(mdlh, "SearchDepth", 1, "BlockType", "Inport");

for i = 1:numel(inhs)
    inh = inhs(i);

    name = get_param(inh, "Name");

    inTypes = string(get_param(inh, "OutDataTypeStr"));
    isBus = contains(inTypes, "Bus:");
    isEnum = contains(inTypes, "Enum:");

    inOutSignals = get_param(inh, "PortHandles");
    inputSignals = get_param(inOutSignals.Outport, "SignalHierarchy");

    if isBus

        if isempty(inputSignals.BusObject)
            error(inTypes + " definition not found")
        end

        creatorName = "creator" + i;
        fromName = name;
        toName = "mdl/" + i;

        switch nvp.BusAs
            case "Ports"
                util.sl.signalsToBus(inputSignals, wrapperName, fromName, toName, creatorName);
            otherwise
                util.sl.vectorToBus(inputSignals, wrapperName, fromName, toName, creatorName, 0, true, "CastTo", nvp.VectorDataType);
        end
    elseif isEnum

        name = cleanName(name);

        % The CIGRE ABI carries enums as int32; cast on the inside of the
        % wrapper so the outside port stays a plain integer.
        c = add_block("simulink/Quick Insert/Signal Attributes/Cast", wrapperName + "/Convert" + name);
        set_param(c, "OutDataTypeStr", inTypes);
        l = add_line(wrapperName, "Convert" + name + "/1", "mdl/" + i);

        in = add_block("built-in/Inport", wrapperName + "/" + name);
        set_param(in, "OutDataTypeStr", "int32");
        add_line(wrapperName, name + "/1", "Convert" + name + "/" + 1);

        signalName = inputSignals.SignalName;
        set_param(l, "Name", signalName);

    else
        name = cleanName(name);
        add_block("built-in/Inport", wrapperName + "/" + name);
        l = add_line(wrapperName, name + "/1", "mdl/" + i);

        signalName = inputSignals.SignalName;
        set_param(l, "Name", signalName);
    end

end


%% Output
outh = find_system(mdlh, "SearchDepth", 1, "BlockType", "Outport");
for i = 1:numel(outh)

    outTypes = string(get_param(outh(i), "OutDataTypeStr"));

    isBus = contains(outTypes, "Bus:");
    isEnum = contains(outTypes, "Enum:");

    name = get_param(outh(i), "Name");

    if isBus

        bus = util.sl.loadBus(model, outTypes);

        selectorName = "selector" + i;
        toName = name;
        fromName = "mdl/" + i;

        switch nvp.BusAs
            case "Ports"
                util.sl.busToSignals(bus, wrapperName, fromName, toName, selectorName);
            otherwise
                util.sl.busToVector(bus, wrapperName, fromName, toName, selectorName, true);
        end

    elseif isEnum

        name = cleanName(name);

        % Mirror of the input-side cast: the wrapper's port is int32, the
        % inside of the model expects the enum class.
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

ip = get_param(mdlRef, "InstanceParameters");

if ~isempty(ip)

    mws = get_param(model, "ModelWorkspace");
    p = mws.whos;
    wws = get_param(wrapperName, "ModelWorkspace");

    ipNames = string({ip.Name});
    for i = 1:numel(p)
        name = p(i).name;
        var = mws.getVariable(name);
        assignin(wws, name, var);

        idx = (ipNames == name);
        if any(idx)
            % InstanceParameters.Value is a char literal that Simulink
            % eval's in the wrapper workspace at compile time.
            ip(idx).Value = char(util.valToString(var.Value));
        end
    end

    % InstanceParameters' Path field was renamed to FullPath in newer
    % releases; rename in-place so set_param succeeds across versions.
    ipNew = arrayfun(@(x) renameStructField(x, {"Path"}, {"FullPath"}), ip);
    set_param(mdlRef, "InstanceParameters", ipNew);
end

end

function name = cleanName(name)
arguments
    name (1,1) string
end

% Slashes in Simulink block paths are escaped by doubling them.
name = strrep(name, "/", "//");

end
