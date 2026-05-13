function [modelPath, info] = importDLL(dllPath, nvp)
% IMPORTDLL  Import a CIGRE-compliant DLL into Simulink as a block.
%
%   modelPath = cigre.importDLL(dllPath)
%
%   Loads the CIGRE DLL at dllPath, introspects it via Model_GetInfo(),
%   and creates a Simulink model (.slx) containing a pre-configured
%   Level-2 MATLAB S-Function block that wraps the DLL.
%
%   Input/output port count, data types and widths are set automatically
%   from the DLL metadata, as is the fixed-step sample time.  A block mask
%   is added with one editable field per CIGRE parameter (default values
%   pre-filled from the DLL).
%
%   [modelPath, info] = cigre.importDLL(___) also returns the parsed DLL
%   model information as a cigre.importer.ModelInfo object.
%
% Name-Value Arguments
% --------------------
%   Header       (string)  Path to the DLL header file.  Defaults to a
%                file with the same base name as the DLL and a .h extension
%                in the same directory.  (Not used for introspection —
%                the MEX helper reads the DLL directly — but stored in the
%                block so that the S-Function can load the library at
%                simulation time via loadlibrary.)
%
%   OutputFolder (string)  Folder in which the generated model is saved.
%                Default: current working directory.
%
%   BlockName    (string)  Name used for both the model and the block.
%                Default: derived from the DLL's ModelName field.
%
%   OpenModel    (logical) Open the model in Simulink after creation.
%                Default: true.
%
% Example
% -------
%   modelPath = cigre.importDLL('C:\dlls\MyController.dll');
%
%   modelPath = cigre.importDLL('MyController.dll', ...
%       'Header',       'C:\dlls\MyController.h', ...
%       'OutputFolder', 'C:\models');

    arguments
        dllPath (1,1) string
        nvp.Header (1,1) string = fullfile(cigreRoot, "src", "CIGRESource", "IEEE_Cigre_DLLInterface.h")
        nvp.OutputFolder (1,1) string = string(pwd)
        nvp.BlockName (1,1) string = string(missing)
        nvp.OpenModel (1,1) logical = true
    end

    dllPath = resolvePath(dllPath);
    if ~isfile(dllPath)
        error("CIGRE:importDLL:DLLNotFound", ...
            "CIGRE DLL not found: %s", dllPath);
    end

    [dllDir, dllBase, ~] = fileparts(dllPath);

    if ismissing(nvp.Header)
        headerPath = fullfile(dllDir, dllBase + ".h");
    else
        headerPath = resolvePath(nvp.Header);
    end
    if ~isfile(headerPath)
        error("CIGRE:importDLL:HeaderNotFound", ...
            "DLL header not found: %s\nSpecify it explicitly via the Header argument.", ...
            headerPath);
    end

    % ModelInfo.fromDLL uses a MEX helper so the DLL is read once and not
    % kept loaded; the S-Function reloads it via loadlibrary at sim time.
    info = cigre.importer.ModelInfo.fromDLL(dllPath);

    if ismissing(nvp.BlockName)
        if strtrim(info.Name) ~= ""
            blockName = matlab.lang.makeValidName(info.Name);
        else
            blockName = matlab.lang.makeValidName(dllBase);
        end
    else
        blockName = nvp.BlockName;
    end

    outputFolder = nvp.OutputFolder;
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    modelName = blockName;
    modelPath = fullfile(outputFolder, modelName + ".slx");

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    hModel = new_system(modelName);
    blockPath = modelName + "/" + blockName;

    try
        addLevel2SFBlock(blockPath);

        paramVarNames = applyMask(blockPath, info, dllPath, headerPath);

        % Simulink resolves each name in the mask workspace and feeds the
        % result to block.DialogPrm(i) in order:
        %   1 = DLLPath, 2 = HeaderPath, 3..N+2 = parameter values.
        set_param(char(blockPath), "Parameters", ...
            char(strjoin(paramVarNames, ", ")));

        save_system(hModel, char(modelPath));

        if nvp.OpenModel
            open_system(hModel);
        else
            close_system(hModel, 0);
        end

    catch ME
        if bdIsLoaded(modelName)
            close_system(modelName, 0);
        end
        if isfile(modelPath)
            delete(modelPath);
        end
        rethrow(ME);
    end

    modelPath = string(modelPath);

    fprintf("CIGRE DLL imported successfully.\n");
    fprintf("  Model      : %s  v%s\n", info.Name, info.Version);
    fprintf("  Inputs     : %d\n", numel(info.Inputs));
    fprintf("  Outputs    : %d\n", numel(info.Outputs));
    fprintf("  Parameters : %d\n", numel(info.Parameters));
    fprintf("  Saved to   : %s\n", modelPath);
end

% ======================================================================= %
%  Local helpers
% ======================================================================= %

function p = resolvePath(p)
arguments
    p (1,1) string
end
    resolved = which(p);
    if ~isempty(resolved)
        p = string(resolved);
    else
        p = string(p);
    end
end

function addLevel2SFBlock(blockPath)
arguments
    blockPath (1,1) string
end
% Adds a Level-2 MATLAB S-Function block whose library path was renamed
% between releases. The new name is tried first; the older name remains
% as a fallback for legacy installs.
    names = [...
        "simulink/User-Defined Functions/Level-2 MATLAB S-Function", ...
        "simulink/User-Defined Functions/Level-2 M-file S-Function"];
    added = false;
    for k = 1:numel(names)
        try
            add_block(names(k), char(blockPath), ...
                "FunctionName", "cigreDLLSFunction", ...
                "Position", [100, 100, 300, 200]);
            added = true;
            break
        catch
        end
    end
    if ~added
        error("CIGRE:importDLL:BlockNotFound", ...
            "Could not add a Level-2 MATLAB S-Function block. Check that Simulink is installed.");
    end
end

function paramVarNames = applyMask(blockPath, info, dllPath, headerPath)
arguments
    blockPath (1,1) string
    info (1,1) cigre.importer.ModelInfo
    dllPath (1,1) string
    headerPath (1,1) string
end
% applyMask Configure the import block's mask.
%
% Hidden DLLPath/HeaderPath parameters are stored on the mask so the
% S-Function can reload the library at simulation time via loadlibrary.
% Each CIGRE parameter becomes a visible edit field whose mask variable
% name is returned in paramVarNames; the caller wires these into the
% S-Function's 'Parameters' list in order
% [DLLPath, HeaderPath, p1, p2, ...].

    mask = Simulink.Mask.create(char(blockPath));

    descLines = ["CIGRE DLL Block", ""];
    if info.Name ~= ""
        descLines(end+1) = sprintf("Model   : %s", info.Name);
    end
    if info.Version ~= ""
        descLines(end+1) = sprintf("Version : %s", info.Version);
    end
    if info.SampleTime > 0
        descLines(end+1) = sprintf("Ts      : %g s", info.SampleTime);
    end
    if strtrim(info.Description) ~= ""
        descLines(end+1) = "";
        descLines(end+1) = char(info.Description);
    end
    mask.Description = strjoin(descLines, newline);

    % Path values are stored as MATLAB-quoted char literals (e.g.
    % 'C:\it''s\dll.dll') because the mask workspace eval's them.
    escapePath = @(p) char("'" + strrep(string(p), "'", "''") + "'");

    pDLL = mask.addParameter("Type", "edit", ...
        "Name", "DLLPath", ...
        "Prompt", "DLL file path", ...
        "Value", escapePath(dllPath), ...
        "Tunable", "off");
    pDLL.Visible = "off";

    pHdr = mask.addParameter("Type", "edit", ...
        "Name", "HeaderPath", ...
        "Prompt", "Header file path", ...
        "Value", escapePath(headerPath), ...
        "Tunable", "off");
    pHdr.Visible = "off";

    paramVarNames = ["DLLPath", "HeaderPath"];

    for i = 1:numel(info.Parameters)
        p = info.Parameters(i);
        vid = matlab.lang.makeValidName(string(p.Name));

        % Two parameters can sanitise to the same MATLAB identifier;
        % uniqueness guards prevent overwriting an earlier slot.
        vid = matlab.lang.makeUniqueStrings(vid, paramVarNames);

        prompt = string(p.Name);
        unit = strtrim(string(p.Unit));
        if unit ~= ""
            prompt = prompt + " [" + unit + "]";
        end

        mp = mask.addParameter("Type", "edit", ...
            "Name", char(vid), ...
            "Prompt", char(prompt), ...
            "Value", mat2str(p.DefaultValue), ...
            "Tunable", "on");

        desc = strtrim(string(p.Description));
        if desc ~= ""
            try
                mp.Tooltip = char(desc);
            catch
                % Tooltip is unsupported on this MATLAB release; mask
                % is still functional without it.
            end
        end

        grp = strtrim(string(p.GroupName));
        if grp ~= ""
            try
                mp.GroupName = char(grp);
            catch
                % GroupName is unsupported on this MATLAB release.
            end
        end

        paramVarNames(end+1) = vid; %#ok<AGROW>
    end

    displayLines = string.empty(1,0);
    for i = 1:numel(info.Inputs)
        % Single quotes inside port labels would terminate the
        % port_label('...') literal; double them up to escape.
        lbl = strrep(char(string(info.Inputs(i).Name)), "'", "''");
        displayLines(end+1) = sprintf("port_label('input',%d,'%s')", i, lbl); %#ok<AGROW>
    end
    for i = 1:numel(info.Outputs)
        lbl = strrep(char(string(info.Outputs(i).Name)), "'", "''");
        displayLines(end+1) = sprintf("port_label('output',%d,'%s')", i, lbl); %#ok<AGROW>
    end
    if ~isempty(displayLines)
        mask.Display = strjoin(displayLines, newline);
    end
end
