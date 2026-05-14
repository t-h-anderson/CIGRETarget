function baseline = captureSimulinkBaseline(mdlName, inputs, simulinkParameters, stopTime, timeStep)
% captureSimulinkBaseline Run a Simulink model and return the output timetable.
%
%   baseline = cigre.internal.captureSimulinkBaseline( ...
%       mdlName, inputs, simulinkParameters, stopTime, timeStep)
%
% Used both by the test suite (to produce a reference baseline that DLL
% output is compared against) and by cigre.internal.buildDLLWithDebug to
% give super users a Simulink-derived reference when debugging the DLL
% in Visual Studio.
%
% Inputs:
%   mdlName            - the wrapper model name (e.g. "<Model>_wrap").
%   inputs             - a timetable matching the model's Inport
%                        interface, one variable per Inport, with time as
%                        the row times.
%   simulinkParameters - struct array with .Name and .Value fields
%                        describing the InstanceParameters / model
%                        workspace values to apply to the run.
%   stopTime           - simulation stop time (seconds, double).
%   timeStep           - fixed sample step (seconds, double).
%
% Returns:
%   baseline - the extractData() timetable that runDLL / buildDLLWithDebug
%              uses as the reference signal stream.
arguments
    mdlName (1,1) string
    inputs timetable
    simulinkParameters (1,:) struct
    stopTime (1,1) double
    timeStep (1,1) double
end

[~, cMdl] = util.loadSystem(mdlName); %#ok<ASGLU>

simIn = Simulink.SimulationInput(mdlName);
simIn = configureSimInputs(simIn, mdlName, inputs);
simIn = configureSimParameters(simIn, mdlName, simulinkParameters);

simIn = setModelParameter(simIn, "StopTime", string(stopTime), ...
    "FixedStep", string(timeStep));

results = sim(simIn);
if isempty(results.yout{1}.Values.Data)
    % R2025a occasionally returns empty yout on the first sim call for
    % some models; re-running produces results.
    results = sim(simIn);
end

baseline = extractData(results);
end


function simIn = configureSimInputs(simIn, mdlName, inputs)
arguments
    simIn
    mdlName (1,1) string
    inputs timetable
end

try
    if verLessThan("MATLAB", "25.1") %#ok<VERLESSMATLAB>
        inDS = createInputDataset(mdlName);
    else
        inDS = createInputDataset(mdlName, "UpdateDiagram", false);
    end
    nInputs = numel(inDS.getElementNames());
catch me
    if me.identifier == "sl_sta:editor:modelNoExternalInterface"
        nInputs = 0;
    else
        rethrow(me)
    end
end

if nInputs == 0
    return
end

if size(inputs, 2) ~= nInputs
    error("cigre:captureSimulinkBaseline:InputCountMismatch", ...
        "Inputs timetable has %d columns but model %s expects %d Inports.", ...
        size(inputs, 2), mdlName, nInputs);
end

for i = 1:nInputs
    col = inputs(:, i);

    if istimetable(col)
        vals = col.Variables;
        if numel(size(vals)) > 2
            % t x m x n needs permuting to m x n x t for timeseries.
            vals = permute(vals, [(2:numel(size(vals))), 1]);
        end
        sig = timeseries(vals, seconds(col.Time));
        sig = sig.setinterpmethod("nearest");
        sig = sig.setuniformtime("StartTime", 0, ...
            "EndTime", seconds(max(inputs.Time(end))));
        sig.Name = inputs.Properties.VariableNames{i};
        inDS{i} = sig;
    else
        inDS{i} = col;
    end
end

simIn = simIn.setExternalInput(inDS);
end


function simIn = configureSimParameters(simIn, mdlName, simulinkParameters)
arguments
    simIn
    mdlName (1,1) string
    simulinkParameters (1,:) struct
end

ip = get_param(simIn.ModelName + "/mdl", "InstanceParameters");
for i = 1:numel(simulinkParameters)
    name = simulinkParameters(i).Name;
    val = simulinkParameters(i).Value;
    % Parameter values are stored as char on InstanceParameters.
    val = char(util.valToString(val));
    idx = (string({ip.Name}) == name);
    if any(idx)
        ip(idx).Value = val;
    else
        % Resolve from the source model's workspace / data dictionary.
        mdl = erase(mdlName, "_wrap");
        param = util.findParam(mdl, name);
        if isa(param, "Simulink.data.dictionary.Entry")
            simIn = simIn.setVariable(name, eval(val));
        elseif isfield(param, "Value") || isprop(param, "Value")
            param.Value = eval(val);
            simIn = simIn.setVariable(name, param, "Workspace", mdl);
        else
            param = eval(val);
            simIn = simIn.setVariable(name, param, "Workspace", mdl);
        end
    end
end

if ~isempty(ip)
    % InstanceParameters' Path field was renamed to FullPath in newer
    % releases; rename in-place so set works across versions.
    ipNew = arrayfun(@(x) renameStructField(x, "Path", "FullPath"), ip);
    simIn = simIn.setBlockParameter(simIn.ModelName + "/mdl", ...
        "InstanceParameters", ipNew);
end
end
