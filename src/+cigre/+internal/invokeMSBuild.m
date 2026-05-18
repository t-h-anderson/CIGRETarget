function dllPath = invokeMSBuild(slnPath, projectName, nvp)
% invokeMSBuild Build a generated VS solution from MATLAB.
%
%   dllPath = cigre.internal.invokeMSBuild(slnPath, projectName)
%
% Locates MSBuild via cigre.internal.findVSInstallation, runs it on
% the supplied .sln in Debug | x64 configuration, and returns the
% absolute path to the produced DLL (under <slnDir>/x64/Debug). On
% build failure the MSBuild output is surfaced in the error message.
%
% Inputs:
%   slnPath     - .sln to build.
%   projectName - bare project name (i.e. the part before .dll in the
%                 expected output, e.g. "MyModel_CIGRE").
%
% Name-Value Arguments:
%   Verbosity - MSBuild verbosity (default "minimal"). Use "quiet" to
%               suppress everything but errors, "normal" for a full
%               build log.
arguments
    slnPath (1,1) string
    projectName (1,1) string
    nvp.Verbosity (1,1) string {mustBeMember(nvp.Verbosity, ["quiet", "minimal", "normal", "detailed", "diagnostic"])} = "minimal"
end

if ~isfile(slnPath)
    error("CIGRE:invokeMSBuild:NoSolution", ...
        "Solution file not found: %s", slnPath);
end

[msbuildPath, ~] = cigre.internal.findVSInstallation();

% /p:Configuration=Debug /p:Platform=x64 selects the only configuration
% writeVSProject emits. /nologo suppresses the MSBuild banner;
% /verbosity controls the output volume.
cmd = sprintf( ...
    '"%s" "%s" /p:Configuration=Debug /p:Platform=x64 /nologo /verbosity:%s', ...
    msbuildPath, slnPath, nvp.Verbosity);
fprintf("MSBuild: %s\n", cmd);
[status, output] = system(cmd);
if status ~= 0
    error("CIGRE:invokeMSBuild:BuildFailed", ...
        "MSBuild failed with status %d.\n%s", status, output);
end
fprintf("%s\n", output);

dllPath = fullfile(fileparts(slnPath), "x64", "Debug", projectName + ".dll");
if ~isfile(dllPath)
    error("CIGRE:invokeMSBuild:DLLMissing", ...
        "MSBuild reported success but %s does not exist.\nOutput:\n%s", dllPath, output);
end
dllPath = string(dllPath);
end
