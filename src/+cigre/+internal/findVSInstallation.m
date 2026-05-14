function [msbuildPath, toolset] = findVSInstallation()
% findVSInstallation Locate MSBuild.exe and the matching PlatformToolset.
%
%   [msbuildPath, toolset] = cigre.internal.findVSInstallation()
%
% Uses vswhere.exe (ships at a stable path with the Visual Studio
% Installer) to find the latest VS install with MSBuild, returning
% the absolute MSBuild path and the PlatformToolset string that
% matches its major version (v141 for VS 2017, v142 for VS 2019,
% v143 for VS 2022).
%
% Errors with a clear message if vswhere itself or MSBuild can't be
% located - the caller can then prompt the user to install the
% Desktop development with C++ workload or override the toolset
% manually.

if ~ispc
    error("CIGRE:findVSInstallation:NotWindows", ...
        "Visual Studio MSBuild detection is Windows-only; called on platform '%s'.", computer);
end

programFilesX86 = getenv("ProgramFiles(x86)");
if programFilesX86 == ""
    programFilesX86 = "C:\Program Files (x86)";
end
vswhere = fullfile(programFilesX86, "Microsoft Visual Studio", "Installer", "vswhere.exe");
if ~isfile(vswhere)
    error("CIGRE:findVSInstallation:NoVSWhere", ...
        "vswhere.exe not found at %s. Is the Visual Studio Installer installed?", vswhere);
end

% vswhere -latest -products * -requires Microsoft.Component.MSBuild
%   -find MSBuild\**\Bin\MSBuild.exe
% returns the highest-version MSBuild belonging to any VS install
% (Community/Professional/Enterprise/BuildTools).
[status, raw] = system(sprintf( ...
    '"%s" -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\\**\\Bin\\MSBuild.exe"', ...
    vswhere));
msbuildPath = strtrim(string(raw));
if status ~= 0 || msbuildPath == "" || ~isfile(msbuildPath)
    error("CIGRE:findVSInstallation:NoMSBuild", ...
        "vswhere could not locate MSBuild.exe (status %d).\nOutput: %s", status, raw);
end

% Major VS version determines the PlatformToolset MSBuild expects in
% the .vcxproj. installationVersion is "16.x" for VS 2019, "17.x" for
% VS 2022, etc.
[status, raw] = system(sprintf( ...
    '"%s" -latest -products * -property installationVersion', vswhere));
toolset = "v142";
if status == 0
    versionStr = strtrim(string(raw));
    if versionStr ~= ""
        major = double(extractBefore(versionStr, "."));
        switch major
            case 15
                toolset = "v141";
            case 16
                toolset = "v142";
            case 17
                toolset = "v143";
            otherwise
                % Unknown major version - fall through to v142 default.
                % Newer VS releases tend to also ship v142 / v143 side
                % by side, so this is the safest landing zone.
        end
    end
end
end
