function slnPath = writeVSProject(model, workFolder, nvp)
% writeVSProject Emit a VS solution + project for a CIGRE DLL debug build.
%
%   slnPath = cigre.internal.writeVSProject(model, workFolder)
%
% Drops a self-contained <model>_CIGRE.sln + <model>_CIGRE.vcxproj into
% workFolder pre-configured for Debug | x64 | DynamicLibrary. The
% generated solution can be double-clicked into Visual Studio, where
% Build > Build Solution links a CIGRE-compatible DLL at
% workFolder\x64\Debug\<model>_CIGRE.dll without any manual project
% setup.
%
% The .vcxproj is rebuilt from CIGREDebug.vcxproj.template on every run,
% so manual edits in VS to the .vcxproj will not survive a re-run of
% cigre.internal.buildDLLWithDebug; tweak the template in source control
% if a permanent change is needed.
%
% Inputs:
%   model      - top-level model name (without the wrapper suffix).
%   workFolder - directory containing the CIGRE-target code generated
%                by cigre.buildDLL (i.e. the cwd after buildDLLWithDebug
%                runs codegen).
%
% Name-Value Arguments:
%   PlatformToolset - VS PlatformToolset value, e.g. "v141" (VS 2017),
%                     "v142" (VS 2019), "v143" (VS 2022). Default
%                     "v142", which is the toolset shipped by both
%                     VS 2019 and VS 2022 - install it via the VS
%                     installer if you only have v143 on disk.
%   WindowsTargetPlatformVersion - Windows SDK version. Default "10.0"
%                     auto-resolves to the latest installed Windows 10
%                     SDK on the user's box; pin to e.g. "10.0.19041.0"
%                     if you need reproducibility.
%
% Returns:
%   slnPath - absolute path to the emitted .sln file.
arguments
    model (1,1) string
    workFolder (1,1) string
    nvp.PlatformToolset (1,1) string = "v142"
    nvp.WindowsTargetPlatformVersion (1,1) string = "10.0"
end

projectName = model + "_CIGRE";
templateDir = fileparts(mfilename("fullpath"));

% Enumerate every .c file the toolchain would compile. The same folders
% feed cigre.internal.buildDLLWithDebug's AdditionalIncludeDirectories
% string, so the lists stay in sync.
sourceDirs = collectSourceDirs(model, workFolder);
sources = collectSources(sourceDirs);

% Headers are cosmetic for the build (the compiler finds them via
% AdditionalIncludeDirectories), but listing them in the .vcxproj gives
% F12 / Solution-Explorer navigation across the generated tree.
headers = collectHeaders(sourceDirs);

% Include set mirrors test.system.tGenerateCigre.doVSBuild plus the
% generated wrapper folder, joined with semicolons per MSBuild
% convention.
includeDirs = [
    fullfile(cigreRoot, "src", "CIGRESource")
    sourceDirs(2:end)  % skip the duplicate CIGRESource entry
    fullfile(matlabroot, "extern", "include")
    fullfile(matlabroot, "simulink", "include")
    fullfile(matlabroot, "rtw", "c", "src")
];
includes = strjoin(string(includeDirs), ";");

% Generate the per-project GUID once per call. VS uses this both to
% match the .sln entry to the .vcxproj and as the ProjectGuid inside
% the .vcxproj. uuid() returns 36 chars with dashes, no braces - exactly
% what the templates expect.
guid = upper(string(cigre.util.uuid()));

sourcesBlock = formatItemEntries(sources, "ClCompile");
headersBlock = formatItemEntries(headers, "ClInclude");

vcxproj = readFile(fullfile(templateDir, "CIGREDebug.vcxproj.template"));
vcxproj = replace(vcxproj, "@@MODEL@@", model);
vcxproj = replace(vcxproj, "@@GUID@@", guid);
vcxproj = replace(vcxproj, "@@INCLUDES@@", includes);
vcxproj = replace(vcxproj, "@@SOURCES@@", sourcesBlock);
vcxproj = replace(vcxproj, "@@HEADERS@@", headersBlock);
vcxproj = replace(vcxproj, "@@TOOLSET@@", nvp.PlatformToolset);
vcxproj = replace(vcxproj, "@@WINSDK@@", nvp.WindowsTargetPlatformVersion);

sln = readFile(fullfile(templateDir, "CIGREDebug.sln.template"));
sln = replace(sln, "@@MODEL@@", model);
sln = replace(sln, "@@GUID@@", guid);

vcxprojPath = fullfile(workFolder, projectName + ".vcxproj");
slnPath = fullfile(workFolder, projectName + ".sln");
writeFile(vcxprojPath, vcxproj);
writeFile(slnPath, sln);

end


function dirs = collectSourceDirs(model, workFolder)
% Folders the toolchain compiles from. Order matters: CIGRESource first
% so its declarations win over any duplicates, then the model-specific
% generated tree, then the shared utilities.
dirs = [
    string(fullfile(cigreRoot, "src", "CIGRESource"))
    string(fullfile(workFolder, model + "_wrap_cigre_rtw"))
    string(fullfile(workFolder, "slprj", "ert", "_sharedutils"))
];

% slprj/cigre/<sub>/ holds one subfolder per referenced model. genpath
% returns ; / : joined; split into a string array so we can dedupe.
cigreRoot_ = fullfile(workFolder, "slprj", "cigre");
if isfolder(cigreRoot_)
    sub = genpath(cigreRoot_);
    sub = string(strsplit(sub, pathsep));
    sub = sub(sub ~= "" & arrayfun(@isfolder, sub));
    dirs = [dirs; sub(:)];
end

dirs = unique(dirs, "stable");
end


function files = collectSources(sourceDirs)
% Glob *.c / *.cpp under each source dir, non-recursive.
files = globExtensions(sourceDirs, ["*.c", "*.cpp"]);
if isempty(files)
    error("CIGRE:writeVSProject:NoSources", ...
        "No .c sources found under any of the expected build folders. Did cigre.buildDLL emit code into the work folder?");
end
end


function files = collectHeaders(sourceDirs)
% Glob *.h / *.hpp under each source dir. Absent headers are not an
% error - some folders (e.g. shared utilities) contain only sources.
files = globExtensions(sourceDirs, ["*.h", "*.hpp"]);
end


function files = globExtensions(sourceDirs, exts)
% Non-recursive glob across multiple extensions and dirs. Each dir in
% sourceDirs is already a leaf (collectSourceDirs expanded slprj/cigre
% via genpath), so we don't recurse here.
buckets = cell(numel(sourceDirs) * numel(exts), 1);
k = 0;
for i = 1:numel(sourceDirs)
    for j = 1:numel(exts)
        entries = dir(fullfile(sourceDirs(i), exts(j)));
        k = k + 1;
        if isempty(entries)
            buckets{k} = strings(0, 1);
        else
            buckets{k} = string(fullfile({entries.folder}, {entries.name}))';
        end
    end
end
files = vertcat(buckets{:});
% Deduplicate by absolute path so a file that appears under two parents
% (rare, but possible if the user reuses an output dir) only appears
% once in the .vcxproj.
files = unique(files, "stable");
end


function block = formatItemEntries(files, tag)
% Build a block of <Tag Include="..." /> entries indented to slot into
% the template alongside the surrounding ItemGroup. An empty list
% collapses to a single blank line so the resulting XML still parses.
arguments
    files (:,1) string
    tag (1,1) string
end
if isempty(files)
    block = "";
    return
end
entries = "    <" + tag + " Include=""" + files + """ />";
block = strjoin(entries, newline);
end


function txt = readFile(path)
fid = fopen(path, "r");
if fid < 0
    error("CIGRE:writeVSProject:TemplateMissing", ...
        "Cannot open template at %s", path);
end
closeFid = onCleanup(@() fclose(fid)); %#ok<NASGU>
txt = string(fread(fid, "*char")');
end


function writeFile(path, txt)
fid = fopen(path, "w");
if fid < 0
    error("CIGRE:writeVSProject:WriteFailed", ...
        "Cannot write to %s", path);
end
closeFid = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, char(txt), "char");
end
