function captureParametersFromSimulink(model, outFile, opts)
% captureParametersFromSimulink Write a ParameterConfig.xlsx for a model.
%
%   cigre.util.captureParametersFromSimulink(model, outFile)
%
% Runs cigre.buildDLL with SkipBuild=true to compute the model's CIGRE
% parameter list (the same path cigre.buildDLL would walk for a real
% build), and writes a ParameterConfig.xlsx that can be consumed by
% cigre.config.ParameterConfiguration.fromFile. Each parameter row gets:
%   Name             SimulinkName from the descriptor
%   IsVisible        true (everything visible by default)
%   OverrideDefault  the parameter's current DefaultValue
%
% The file is the same shape cigre.buildDLL's ParameterConfigFile NV-pair
% expects, so callers can edit a few rows by hand and feed it straight
% back into cigre.buildDLL or cigre.internal.buildDLLWithDebug.
%
% Name-Value Arguments:
%   CodeGenFolder - working directory for the throwaway codegen pass
%                   (default: a fresh folder under tempdir).
%   BusAs         - wrapper bus-handling mode passed to cigre.buildDLL
%                   (default: "Vector"; matches cigre.buildDLL's own
%                   default).
%   Verbose       - print the buildDLL banner (default: false).
arguments
    model (1,1) string
    outFile (1,1) string
    opts.CodeGenFolder (1,1) string = ...
        string(fullfile(tempdir, "cigre_captureParams_" + model + "_" + string(feature("getpid"))))
    opts.BusAs (1,1) string {mustBeMember(opts.BusAs, ["Ports", "Vector"])} = "Vector"
    opts.Verbose (1,1) logical = false
end

if ~isfolder(opts.CodeGenFolder)
    mkdir(opts.CodeGenFolder);
end

desc = cigre.buildDLL(model, ...
    "SkipBuild", true, ...
    "CodeGenFolder", opts.CodeGenFolder, ...
    "BusAs", opts.BusAs, ...
    "Verbose", opts.Verbose);

params = desc.Parameters;
n = numel(params);

% Each xlsx row corresponds to one flat parameter entry (struct fields and
% array elements appear as separate rows under their own SimulinkName).
% Use string for Name, logical for IsVisible, and double for
% OverrideDefault to match ParameterConfiguration.fromFile's expectations.
names = strings(n, 1);
visible = true(n, 1);
overrides = nan(n, 1);

for i = 1:n
    names(i) = string(params(i).SimulinkName);
    val = params(i).DefaultValue;
    if isscalar(val) && isnumeric(val)
        overrides(i) = double(val);
    else
        % Non-scalar or non-numeric defaults can't be represented in a
        % single xlsx cell; leave OverrideDefault blank so the loader
        % falls back to the model default at sim time.
        overrides(i) = NaN;
    end
end

rows = table(names, visible, overrides, ...
    'VariableNames', ["Name", "IsVisible", "OverrideDefault"]);

% writetable for an .xlsx target picks up the extension and writes a
% spreadsheet; explicit FileType keeps the behaviour stable across
% releases that have tightened the extension detection rules.
writetable(rows, outFile, "FileType", "spreadsheet");

end
