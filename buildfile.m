function plan = buildfile
% buildfile.m  Build plan for the Simulink to CIGRE Export Tool.
%
% Run with the MATLAB build tool (R2022b and later):
%   buildtool            % run the default (package) task
%   buildtool package    % build the .mltbx toolbox installer

plan = buildplan(localfunctions);
plan.DefaultTasks = "package";
end


function packageTask(~)
% Package the toolbox into a .mltbx installer.
projectRoot = fileparts(mfilename("fullpath"));

% GUID carried over from the previous CIGREPackaging.prj so installed
% copies upgrade in place instead of appearing as a separate toolbox.
identifier = "2e38c43e-de46-4c2e-acf2-d67dda57cadc";
opts = matlab.addons.toolbox.ToolboxOptions(projectRoot, identifier);

opts.ToolboxName = "Simulink to CIGRE Export Tool";
opts.ToolboxVersion = "2.3";
opts.AuthorName = "Tom Anderson";
opts.AuthorEmail = "toma@mathworks.com";
opts.AuthorCompany = "MathWorks";
opts.Description = "Enables developers to create CIGRE compatible DLLs from Simulink models";
opts.ToolboxImageFile = fullfile(projectRoot, "src", "resources", "Logo.png");

% Ship the documentation, top-level README and source tree; everything
% else in the repo (tests, prior releases, project metadata) is omitted.
opts.ToolboxFiles = [
    fullfile(projectRoot, "doc")
    fullfile(projectRoot, "README.md")
    fullfile(projectRoot, "src")
    ];

% Folders placed on the MATLAB path when the toolbox is installed. These
% mirror the CIGRE.prj project path; package folders (+cigre, +util, ...)
% are reached through their parent src/ and are not listed individually.
opts.ToolboxMatlabPath = [
    fullfile(projectRoot, "src")
    fullfile(projectRoot, "src", "CIGRETemplate")
    fullfile(projectRoot, "src", "For2020a")
    fullfile(projectRoot, "src", "advisor")
    fullfile(projectRoot, "src", "target")
    fullfile(projectRoot, "src", "toolchain")
    ];

% Installable from R2020a onward, with no upper release bound.
opts.MinimumMatlabRelease = "R2020a";

opts.OutputFile = fullfile(projectRoot, "Simulink to CIGRE Export Tool.mltbx");

matlab.addons.toolbox.packageToolbox(opts);
fprintf("Packaged %s\n", opts.OutputFile);
end
