function setAllModelsTo(targetRelease, nvp)
% setAllModelsTo Back-port every .slx under test/models/ to a target MATLAB release.
%
%   util.setAllModelsTo("R2020a")
%
% For each model whose saved release is strictly newer than targetRelease:
%   1. Copy the existing file to <modelName>_<currentRelease>.slx alongside
%      it (so the historical version stays in the repo for reference).
%   2. Open the model with its folder temporarily on the path.
%   3. Export it to targetRelease using Simulink.exportToVersion, overwriting
%      the original .slx in place.
%
% Models already at or below targetRelease are skipped.
%
% Inputs:
%   targetRelease - the release tag understood by Simulink.exportToVersion,
%                   e.g. "R2020a", "R2020b", "R2023b".
%
% Name-Value Arguments:
%   ModelsRoot    - root folder to scan (default: <repo>/test/models)
%   Overwrite     - if true, overwrite an existing archive of the same name
%                   rather than skipping the model (default: false)
%
% Notes:
%   * find_mdlrefs cannot resolve sub-model references via name alone unless
%     the containing folder is on the path. setAllModelsTo addpaths each
%     model's folder for the duration of that model's export and removes it
%     again afterwards, so the global path stays clean.
%   * Simulink.exportToVersion may refuse to export when the source uses
%     constructs that didn't exist in the target release; the iteration
%     continues past the failure and reports the offending model so a partial
%     back-port is still useful.
arguments
    targetRelease (1,1) string
    nvp.ModelsRoot (1,1) string = fullfile(cigreRoot, "test", "models")
    nvp.Overwrite (1,1) logical = false
end

if ~isfolder(nvp.ModelsRoot)
    error("util:setAllModelsTo:ModelsRootMissing", ...
        "Models root does not exist: %s", nvp.ModelsRoot);
end

slxFiles = dir(fullfile(nvp.ModelsRoot, "**", "*.slx"));
if isempty(slxFiles)
    warning("No .slx files found under %s.", nvp.ModelsRoot);
    return
end

fprintf("Scanning %d .slx files under %s\n", numel(slxFiles), nvp.ModelsRoot);

skipped = string.empty(0, 1);
exported = string.empty(0, 1);
failed = string.empty(0, 1);

for i = 1:numel(slxFiles)
    slxPath = string(fullfile(slxFiles(i).folder, slxFiles(i).name));
    modelDir = string(slxFiles(i).folder);
    [~, baseName] = fileparts(slxFiles(i).name);

    % Skip files that are already release-tagged archives (X_R2020a.slx
    % style) so repeat invocations don't pile up second-order archives.
    if isReleaseTaggedArchive(baseName)
        continue
    end

    currentRelease = readReleaseTag(slxPath);
    if currentRelease == ""
        fprintf("  ? %-40s  release unknown, skipping\n", baseName);
        skipped(end+1, 1) = baseName; %#ok<AGROW>
        continue
    end

    if ~isReleaseNewer(currentRelease, targetRelease)
        fprintf("  - %-40s  %s <= %s, no action\n", baseName, currentRelease, targetRelease);
        skipped(end+1, 1) = baseName; %#ok<AGROW>
        continue
    end

    archivePath = fullfile(modelDir, baseName + "_" + currentRelease + ".slx");
    if isfile(archivePath) && ~nvp.Overwrite
        fprintf("  ! %-40s  archive already exists at %s; pass Overwrite=true to replace\n", ...
            baseName, archivePath);
        skipped(end+1, 1) = baseName; %#ok<AGROW>
        continue
    end

    try
        copyfile(slxPath, archivePath);

        % Add the model's own folder so load_system can resolve it (and
        % any sibling submodels) by name during export.
        c = onCleanup(@() rmpath(modelDir)); %#ok<NASGU>
        addpath(modelDir);

        % Simulink.exportToVersion requires the model to be loaded and
        % refuses to write back to the file it was loaded from. Load
        % explicitly, export to a sibling temp file, close the model
        % so it releases its file handle, then move the temp file into
        % place over the original.
        load_system(char(baseName));
        tempPath = fullfile(modelDir, baseName + "_exportTmp.slx");
        cleanupTemp = onCleanup(@() deleteIfExists(tempPath)); %#ok<NASGU>

        Simulink.exportToVersion(char(baseName), char(tempPath), char(targetRelease));

        % Close the model and replace the original. Simulink keeps file
        % handles open for transitively-loaded references and the
        % data-dictionary "saveas" sidecar even after a single bdclose,
        % so use bdclose('all') to release everything and retry a few
        % times in case Windows hasn't finished propagating the unlock.
        replaceWithRetry(tempPath, slxPath);

        fprintf("  + %-40s  %s -> %s (archived as %s)\n", ...
            baseName, currentRelease, targetRelease, baseName + "_" + currentRelease + ".slx");
        exported(end+1, 1) = baseName; %#ok<AGROW>
    catch me
        fprintf("  x %-40s  export failed: %s\n", baseName, me.message);
        failed(end+1, 1) = baseName; %#ok<AGROW>
        % If the archive was created but export failed, roll it back so
        % the next run starts from a clean state.
        if isfile(archivePath) && ~isfile(slxPath)
            copyfile(archivePath, slxPath);
        end
        if isfile(archivePath) && nvp.Overwrite
            delete(archivePath);
        end
    end
end

fprintf("\nSummary:\n");
fprintf("  Exported:  %d\n", numel(exported));
fprintf("  Skipped:   %d\n", numel(skipped));
fprintf("  Failed:    %d\n", numel(failed));
if ~isempty(failed)
    fprintf("\nFailed models:\n");
    for j = 1:numel(failed)
        fprintf("  - %s\n", failed(j));
    end
end

end


function tf = isReleaseTaggedArchive(baseName)
% Returns true when the file name ends with _R<digits><letter>, the suffix
% setAllModelsTo writes when it archives an existing model.
tf = ~isempty(regexp(char(baseName), "_R\d{4}[a-z]$", "once"));
end


function rel = readReleaseTag(slxPath)
% Return the release stamp (e.g. "R2026a") for a saved .slx, or "" if it
% cannot be determined.
try
    info = Simulink.MDLInfo(char(slxPath));
    rel = string(info.ReleaseName);
catch
    rel = "";
end
end


function tf = isReleaseNewer(rel1, rel2)
% True iff rel1 (e.g. "R2026a") is strictly newer than rel2.
[year1, letter1] = parseRelease(rel1);
[year2, letter2] = parseRelease(rel2);
if year1 ~= year2
    tf = year1 > year2;
else
    tf = letter1 > letter2;
end
end


function [year, letter] = parseRelease(rel)
% Split "R2026a" into year=2026 and letter='a'. Throws if the form is
% unexpected; callers handle that as "unknown release".
tokens = regexp(char(rel), "^R(\d{4})([a-z])$", "tokens", "once");
if isempty(tokens)
    error("util:setAllModelsTo:BadReleaseFormat", ...
        "Unrecognised release tag '%s'; expected 'R<year><letter>'.", rel);
end
year = double(string(tokens{1}));
letter = tokens{2};
end


function deleteIfExists(p)
% Best-effort cleanup of a stale temp .slx left behind if export fails
% partway through. Silent if the file is already gone.
if isfile(p)
    try
        delete(char(p));
    catch
    end
end
end


function replaceWithRetry(tempPath, destPath)
% Replace destPath with tempPath, robust to Simulink not releasing its
% file handle on Windows. After a load_system + exportToVersion, the
% original .slx can stay pinned by several different cooperating things:
%   - any models still loaded (bdclose('all'))
%   - any open data dictionaries (closeAll('-discard'))
%   - the matching .slxc cache file
%   - Java file handles MATLAB hasn't released yet (java.lang.System.gc)
%   - an active Simulink project tracking the file
%
% Each retry closes one more class of resource and waits longer. The
% replacement itself uses copyfile with the 'f' flag, which on Windows
% can overwrite a file that delete+movefile cannot (different lock-mode
% rules in the underlying CreateFile call).
maxAttempts = 5;
slxcPath = regexprep(char(destPath), '\.slx$', '.slxc');

for attempt = 1:maxAttempts
    try
        bdclose('all');
        try
            Simulink.data.dictionary.closeAll('-discard');
        catch
            % closeAll errors when nothing is open; harmless either way.
        end

        % .slxc holds an indirect reference to the .slx; remove so the
        % next attempt to overwrite the .slx isn't blocked by the cache.
        if isfile(slxcPath)
            try
                delete(slxcPath);
            catch
            end
        end

        % Nudge MATLAB's Java layer to release file handles it might
        % still hold from the load/export sequence.
        try
            java.lang.System.gc();
        catch
        end

        % copyfile with 'f' uses Win32 CopyFile semantics, which can
        % overwrite a file held under shared-read locks where the
        % delete-then-move pair would fail.
        [ok, msg] = copyfile(char(tempPath), char(destPath), 'f');
        if ~ok
            error("util:setAllModelsTo:CopyFailed", "%s", msg);
        end

        % Source copy succeeded; tidy up the temp file.
        try
            delete(char(tempPath));
        catch
        end
        return
    catch me
        if attempt == maxAttempts
            rethrow(me);
        end
        % Progressive back-off. Windows file-lock release after a
        % large Simulink load can take 0.5-2 seconds in practice.
        pause(0.5 * attempt);
    end
end
end
