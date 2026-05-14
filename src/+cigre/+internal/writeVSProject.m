function slnPath = writeVSProject(model, workFolder)
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
% Returns:
%   slnPath - absolute path to the emitted .sln file.
arguments
    model (1,1) string
    workFolder (1,1) string
end

projectName = model + "_CIGRE";
templateDir = fileparts(mfilename("fullpath"));

% Enumerate every .c file the toolchain would compile. The same folders
% feed cigre.internal.buildDLLWithDebug's AdditionalIncludeDirectories
% string, so the lists stay in sync.
sourceDirs = collectSourceDirs(model, workFolder);
sources = collectSources(sourceDirs);

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

% Each source file becomes a <ClCompile Include="..." /> entry. Indent
% to match the existing line containing the @@SOURCES@@ placeholder so
% the resulting XML stays readable in VS's editor.
clItems = strings(numel(sources), 1);
for i = 1:numel(sources)
    clItems(i) = "    <ClCompile Include=""" + sources(i) + """ />";
end
sourcesBlock = strjoin(clItems, newline);

vcxproj = readFile(fullfile(templateDir, "CIGREDebug.vcxproj.template"));
vcxproj = replace(vcxproj, "@@MODEL@@", model);
vcxproj = replace(vcxproj, "@@GUID@@", guid);
vcxproj = replace(vcxproj, "@@INCLUDES@@", includes);
vcxproj = replace(vcxproj, "@@SOURCES@@", sourcesBlock);

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
% Glob *.c (and *.cpp, just in case) under each source dir, non-recursive.
% Each dir in sourceDirs is already a leaf, so we don't recurse.
buckets = cell(numel(sourceDirs), 1);
for i = 1:numel(sourceDirs)
    cFiles = dir(fullfile(sourceDirs(i), "*.c"));
    cppFiles = dir(fullfile(sourceDirs(i), "*.cpp"));
    entries = [cFiles; cppFiles];
    if isempty(entries)
        buckets{i} = strings(0, 1);
        continue
    end
    buckets{i} = string(fullfile({entries.folder}, {entries.name}))';
end
files = vertcat(buckets{:});

if isempty(files)
    error("CIGRE:writeVSProject:NoSources", ...
        "No .c sources found under any of the expected build folders. Did cigre.buildDLL emit code into the work folder?");
end

% Deduplicate by absolute path so a file that appears under two parents
% (rare, but possible if the user reuses an output dir) only compiles
% once.
files = unique(files, "stable");
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
