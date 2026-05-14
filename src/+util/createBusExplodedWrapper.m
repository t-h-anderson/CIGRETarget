function [wrapperName, cWrap] = createBusExplodedWrapper(model, nvp)
arguments
    model (1,1) string
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Ports"
    nvp.NameSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
end

[wrapperName, mdlh, mdlRef, cMdl, cWrap] = setupWrapper(model, nvp, nargout > 1); %#ok<ASGLU>
processInputPorts(mdlh, wrapperName, nvp);
processOutputPorts(mdlh, wrapperName, model, nvp);
Simulink.BlockDiagram.arrangeSystem(wrapperName);
copyInstanceParameters(mdlRef, model, wrapperName);

end


function [wrapperName, mdlh, mdlRef, cMdl, cWrap] = setupWrapper(model, nvp, wantWrapperHandle)
arguments
    model (1,1) string
    nvp struct
    wantWrapperHandle (1,1) logical
end

[mdlh, cMdl] = util.loadSystem(model);

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
if wantWrapperHandle
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

end


function processInputPorts(mdlh, wrapperName, nvp)
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
        l = addEnumCastAdapter(wrapperName, name, "input", i, "int32", inTypes);

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

end


function processOutputPorts(mdlh, wrapperName, model, nvp)
outh = find_system(mdlh, "SearchDepth", 1, "BlockType", "Outport");
for i = 1:numel(outh)

    outTypes = string(get_param(outh(i), "OutDataTypeStr"));

    isBus = contains(outTypes, "Bus:");
    isEnum = contains(outTypes, "Enum:");

    name = get_param(outh(i), "Name");

    outInputSignals = get_param(outh(i), "PortHandles");
    outputSignals = get_param(outInputSignals.Inport, "SignalHierarchy");

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
        l = addEnumCastAdapter(wrapperName, name, "output", i, "int32", outTypes);

        signalName = outputSignals.SignalName;
        set_param(l, "Name", signalName);

    else

        name = cleanName(name);
        add_block("built-in/Outport", wrapperName + "/" + name);
        l = add_line(wrapperName, "mdl/" + i, name + "/1");

        signalName = outputSignals.SignalName;
        set_param(l, "Name", signalName);
    end
end

end


function copyInstanceParameters(mdlRef, model, wrapperName)
ip = get_param(mdlRef, "InstanceParameters");

if isempty(ip)
    return;
end

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


function name = cleanName(name)
arguments
    name (1,1) string
end

% Slashes in Simulink block paths are escaped by doubling them.
name = strrep(name, "/", "//");

end


function lineHandle = addEnumCastAdapter(wrapperName, name, direction, mdlPortIdx, externalType, internalType)
% Wire an enum-typed top-level port through a Cast block so the
% wrapper's external interface uses externalType while the inside of
% the model sees internalType. The CIGRE ABI carries enums as int32,
% so callers pass externalType="int32" and internalType set to the
% enum class string (e.g. "Enum: MyKind") for input direction.
%
% direction:
%   "input"  - external port is an Inport; data flows
%              external -> cast -> mdl. Cast outputs internalType.
%   "output" - external port is an Outport; data flows
%              mdl -> cast -> external port. Cast outputs externalType.
%
% Returns the handle of the line into/out of the model reference
% (cast->mdl for inputs, mdl->cast for outputs) so the caller can
% set its Name to the signal name reported by the source port.
arguments
    wrapperName (1,1) string
    name (1,1) string
    direction (1,1) string {mustBeMember(direction, ["input", "output"])}
    mdlPortIdx (1,1) double
    externalType (1,1) string
    internalType (1,1) string
end

castName = "Convert" + name;
castBlock = add_block("simulink/Quick Insert/Signal Attributes/Cast", ...
    wrapperName + "/" + castName);

if direction == "input"
    set_param(castBlock, "OutDataTypeStr", internalType);
    lineHandle = add_line(wrapperName, castName + "/1", "mdl/" + mdlPortIdx);

    portBlock = add_block("built-in/Inport", wrapperName + "/" + name);
    set_param(portBlock, "OutDataTypeStr", externalType);
    add_line(wrapperName, name + "/1", castName + "/1");
else
    set_param(castBlock, "OutDataTypeStr", externalType);
    lineHandle = add_line(wrapperName, "mdl/" + mdlPortIdx, castName + "/1");

    portBlock = add_block("built-in/Outport", wrapperName + "/" + name);
    set_param(portBlock, "OutDataTypeStr", externalType);
    add_line(wrapperName, castName + "/1", name + "/1");
end

end
