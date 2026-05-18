function [simulinkParameters, cigreParameters] = resolveParameters(desc, paramConfig)
% resolveParameters Build SimulinkParameters / CIGREParameters from a model.
%
%   [simulinkParameters, cigreParameters] = ...
%       cigre.internal.resolveParameters(desc, paramConfig)
%
% Derives both parameter struct arrays purely from the model
% description and a cigre.config.ParameterConfiguration; the test
% suite's gatherParameters delegates here. Both returns are arrays of
% (.Name, .Value).
%
%   simulinkParameters - every Simulink parameter the wrapper exposes,
%                        each carrying the effective default after
%                        applying any OverrideDefault entries from the
%                        config (used to populate the Simulink baseline
%                        sim's InstanceParameters).
%   cigreParameters    - only the visible parameters (per the config),
%                        which is what the DLL's external Parameters
%                        struct expects at runtime.
arguments
    desc
    paramConfig (1,1) cigre.config.ParameterConfiguration
end

simulinkParameters = struct("Name", {}, "Value", {});
cigreParameters = struct("Name", {}, "Value", {});

simulinkParams = desc.Parameters;
for i = 1:numel(simulinkParams)
    p = simulinkParams(i);
    val = p.DefaultValue;
    try
        val = cast(val, p.BaseType);
    catch
        % Not castable (e.g. a struct default) - leave as-is.
    end
    simulinkParameters(i) = struct("Name", p.SimulinkName, "Value", val);
end

allCigreParams = desc.CIGREParameters;
[visibleParams, hiddenParams] = paramConfig.partitionParameters(allCigreParams);

% Visible + hidden defaults flow into SimulinkParameters; only visible
% are exposed as CIGREParameters (hidden are baked into the DLL).
allEffective = [visibleParams, hiddenParams];
for i = 1:numel(allEffective)
    p = allEffective(i);
    simulinkParameters = applyEffectiveDefault(simulinkParameters, ...
        p.SimulinkName, p.DefaultValue);
end

for j = 1:numel(visibleParams)
    p = visibleParams(j);
    val = p.DefaultValue;
    try
        if p.BaseType == "boolean"
            val = boolean(val);
        else
            val = cast(val, p.BaseType);
        end
    catch
        warning("Could not cast CIGRE parameter %s to %s", p.CIGREName, p.BaseType);
    end
    cigreParameters(end+1) = struct("Name", p.CIGREName, "Value", val); %#ok<AGROW>
end
end


function simulinkParams = applyEffectiveDefault(simulinkParams, cigreSimulinkName, effectiveDefault)
% Mirror of test.system.tGenerateCigre.applyEffectiveDefault. The
% CIGRE SimulinkName may include array indexing or nested struct
% field paths; the root identifier matches an existing entry in
% simulinkParams.
arguments
    simulinkParams  (1,:) struct
    cigreSimulinkName (1,1) string
    effectiveDefault (1,1) double
end

bracketPos = strfind(cigreSimulinkName, "[");
dotPos = strfind(cigreSimulinkName, ".");
splitPos = min([bracketPos, dotPos, strlength(cigreSimulinkName) + 1]);
rootName = extractBefore(cigreSimulinkName + " ", splitPos);

entryIdx = find(string({simulinkParams.Name}) == rootName, 1);
if isempty(entryIdx)
    return
end

currentValue = simulinkParams(entryIdx).Value;

if ~isempty(bracketPos) && (isempty(dotPos) || bracketPos(1) < dotPos(1))
    zeroBasedIndex = str2double(extractBetween(cigreSimulinkName, "[", "]"));
    currentValue(zeroBasedIndex + 1) = cast(effectiveDefault, class(currentValue));
elseif ~isempty(dotPos)
    fieldPath = extractAfter(cigreSimulinkName, ".");
    currentValue = setNestedField(currentValue, fieldPath, effectiveDefault);
else
    currentValue = cast(effectiveDefault, class(currentValue));
end

simulinkParams(entryIdx).Value = currentValue;
end


function s = setNestedField(s, fieldPath, value)
arguments
    s
    fieldPath (1,1) string
    value     (1,1) double
end
dotPos = strfind(fieldPath, ".");
if isempty(dotPos)
    s.(fieldPath) = cast(value, class(s.(fieldPath)));
else
    head = extractBefore(fieldPath, dotPos(1));
    tail = extractAfter(fieldPath, dotPos(1));
    s.(head) = setNestedField(s.(head), tail, value);
end
end
