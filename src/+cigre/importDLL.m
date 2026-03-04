function [modelPath, info] = importDLL(dllPath, nvp)
% IMPORTDLL  Import a CIGRE-compliant DLL into Simulink as a block.
%
%   modelPath = cigre.importDLL(dllPath)
%
%   Loads the CIGRE DLL at dllPath, introspects it via Model_GetInfo(),
%   and creates a Simulink model (.slx) containing a pre-configured block
%   that wraps the DLL.  The block is an instance of cigreDLLSFunction
%   (Level-2 MATLAB S-Function) masked with named fields for each DLL
%   parameter.
%
%   Input / output port count, data types and widths are set automatically
%   from the DLL metadata, as is the fixed-step sample time.
%
%   [modelPath, info] = cigre.importDLL(___) also returns the parsed DLL
%   model information as a cigre.importer.ModelInfo object.
%
% Name-Value Arguments
% --------------------
%   Header       (string) Path to the DLL header file.  Defaults to a
%                file with the same base name as the DLL and a .h extension
%                in the same directory.
%
%   OutputFolder (string) Folder in which the generated model is saved.
%                Default: current working directory.
%
%   BlockName    (string) Name used for both the model and the block inside
%                it.  Default: derived from the DLL's ModelName field.
%
%   OpenModel    (logical) Whether to open the model in Simulink after
%                creation.  Default: true.
%
% Example
% -------
%   % Create a model from MyController.dll (header must be MyController.h
%   % in the same folder, or specified via Header=)
%   modelPath = cigre.importDLL('C:\dlls\MyController.dll');
%
%   % Specify header and output folder explicitly
%   modelPath = cigre.importDLL('MyController.dll', ...
%       'Header',       'C:\dlls\MyController.h', ...
%       'OutputFolder', 'C:\models');

    arguments
        dllPath      (1,1) string
        nvp.OutputFolder (1,1) string  = string(pwd)
        nvp.BlockName    (1,1) string  = string(missing)
        nvp.OpenModel    (1,1) logical = true
    end

    % ------------------------------------------------------------------ %
    %  Resolve DLL path
    % ------------------------------------------------------------------ %
    dllPath = resolvePath(dllPath);
    if ~isfile(dllPath)
        error('CIGRE:importDLL:DLLNotFound', ...
            'CIGRE DLL not found: %s', dllPath);
    end

    [dllDir, dllBase, ~] = fileparts(dllPath);

    % ------------------------------------------------------------------ %
    %  Load DLL and read model info
    % ------------------------------------------------------------------ %
    cigreSrcDir = fullfile(cigreRoot(), 'src', 'CIGRESource');
    alias = "cigre_import_" + matlab.lang.makeValidName(dllBase) ...
            + "_" + cigre.util.uuid();


    src = fullfile(cigreRoot, "src", "CIGRESource");
    header = fullfile(src, "IEEE_Cigre_DLLInterface.h");

    unloadIfLoaded(alias);
    loadlibrary(char(dllPath), char(header), ...
        'includepath', cigreSrcDir, ...
        'alias',       char(alias));
    cleanupLib = onCleanup(@() unloadIfLoaded(alias)); 

    info = cigre.importer.ModelInfo.fromLoadedDLL(alias);

    % ------------------------------------------------------------------ %
    %  Determine block / model name
    % ------------------------------------------------------------------ %
    if ismissing(nvp.BlockName)
        if strtrim(info.Name) ~= ""
            blockName = matlab.lang.makeValidName(info.Name);
        else
            blockName = matlab.lang.makeValidName(dllBase);
        end
    else
        blockName = nvp.BlockName;
    end

    % ------------------------------------------------------------------ %
    %  Ensure output folder exists
    % ------------------------------------------------------------------ %
    outputFolder = nvp.OutputFolder;
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    modelName = blockName;
    modelPath = fullfile(outputFolder, modelName + ".slx");

    % ------------------------------------------------------------------ %
    %  Create Simulink model
    % ------------------------------------------------------------------ %
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    hModel    = new_system(modelName);
    blockPath = modelName + "/" + blockName;

    try
        % --- Add Level-2 S-Function block --- %
        add_block('built-in/S-Function', char(blockPath), ...
            'FunctionName', 'cigreDLLSFunction', ...
            'Parameters',   buildSFParamString(dllPath, header, info.Parameters), ...
            'Position',     [100, 100, 300, 200]);

        % --- Apply block mask with DLL parameter fields --- %
        applyMask(blockPath, info, dllPath, header);

        % --- Save model --- %
        save_system(hModel, char(modelPath));

        if nvp.OpenModel
            open_system(hModel);
        else
            close_system(hModel, 0);
        end

    catch ME
        % Clean up any partially created model
        if bdIsLoaded(modelName)
            close_system(modelName, 0);
        end
        if isfile(modelPath)
            delete(modelPath);
        end
        rethrow(ME);
    end

    modelPath = string(modelPath);

    fprintf('CIGRE DLL imported successfully.\n');
    fprintf('  Model : %s (%s v%s)\n', info.Name, info.Name, info.Version);
    fprintf('  Inputs: %d   Outputs: %d   Parameters: %d\n', ...
        numel(info.Inputs), numel(info.Outputs), numel(info.Parameters));
    fprintf('  Saved : %s\n', modelPath);
end

% ======================================================================= %
%  Local helpers
% ======================================================================= %

function p = resolvePath(p)
% Try which() first, fall back to the string as-is.
    resolved = which(p);
    if ~isempty(resolved)
        p = string(resolved);
    else
        p = string(p);
    end
end

function str = buildSFParamString(dllPath, headerPath, paramInfoArray)
% Build the comma-separated parameter string for the S-Function block.
% Format: 'dllPath','headerPath',defaultVal1,defaultVal2,...
    parts    = ["'" + strrep(dllPath, "'", "''") + "'", ...
                "'" + strrep(headerPath, "'", "''") + "'"];
    for i = 1:numel(paramInfoArray)
        parts(end+1) = string(mat2str(paramInfoArray(i).DefaultValue)); %#ok<AGROW>
    end
    str = char(strjoin(parts, ','));
end

function applyMask(blockPath, info, dllPath, headerPath)
% Create a Simulink mask on blockPath exposing DLL parameters and metadata.

    mask = Simulink.Mask.create(char(blockPath));

    % Mask description
    descLines = {sprintf('CIGRE DLL Block'), ''};
    if info.Name ~= ""
        descLines{end+1} = sprintf('Model   : %s', info.Name);
    end
    if info.Version ~= ""
        descLines{end+1} = sprintf('Version : %s', info.Version);
    end
    if info.SampleTime > 0
        descLines{end+1} = sprintf('Ts      : %g s', info.SampleTime);
    end
    if info.Description ~= ""
        descLines{end+1} = '';
        descLines{end+1} = char(info.Description);
    end
    mask.Description = strjoin(descLines, newline);

    % ---- Hidden parameters for DLL/header paths (read-only in mask) ---- %
    pDLL = mask.addParameter('Type', 'edit', ...
        'Name',       'DLLPath', ...
        'Prompt',     'DLL file path', ...
        'Value',      char("'" + strrep(dllPath, "'", "''") + "'"), ...
        'Tunable',    'off');
    pDLL.Visible = 'off'; %#ok<NASGU>

    pHdr = mask.addParameter('Type', 'edit', ...
        'Name',       'HeaderPath', ...
        'Prompt',     'Header file path', ...
        'Value',      char("'" + strrep(headerPath, "'", "''") + "'"), ...
        'Tunable',    'off');
    pHdr.Visible = 'off'; %#ok<NASGU>

    % ---- One mask parameter per CIGRE DLL parameter ---- %
    for i = 1:numel(info.Parameters)
        p    = info.Parameters(i);
        pId  = matlab.lang.makeValidName(p.Name);

        % Build prompt label
        prompt = p.Name;
        if p.Unit ~= "" && strtrim(p.Unit) ~= ""
            prompt = prompt + " [" + strtrim(p.Unit) + "]";
        end

        % Build tooltip from description
        if p.Description ~= "" && strtrim(p.Description) ~= ""
            tooltip = char(strtrim(p.Description));
        else
            tooltip = char(prompt);
        end

        % Group label from GroupName
        groupLabel = "";
        if p.GroupName ~= "" && strtrim(p.GroupName) ~= ""
            groupLabel = strtrim(p.GroupName);
        end

        mp = mask.addParameter('Type',   'edit', ...
            'Name',     char(pId), ...
            'Prompt',   char(prompt), ...
            'Value',    mat2str(p.DefaultValue), ...
            'Tunable',  'on');

        % Set tooltip if API supports it (R2020b+)
        try
            mp.Tooltip = tooltip;
        catch
        end

        % Set group if API supports it (R2022a+)
        if groupLabel ~= ""
            try
                mp.GroupName = char(groupLabel);
            catch
            end
        end
    end

    % ---- Mask initialization: forward parameter values to S-Function ---- %
    % The S-Function reads block.DialogPrm(i) in order, so the mask params
    % must be listed in the same order: DLLPath, HeaderPath, p1, p2, ...
    initParts = {"DLLPath", "HeaderPath"};
    for i = 1:numel(info.Parameters)
        pId = matlab.lang.makeValidName(info.Parameters(i).Name);
        initParts{end+1} = char(pId); %#ok<AGROW>
    end

    % Add port labels from signal names
    if ~isempty(info.Inputs)
        inLabels = arrayfun(@(s) sprintf("port_label('input',%d,'%s')", ...
            find(info.Inputs == s, 1), strrep(s.Name, "'", "''")), ...
            info.Inputs, 'UniformOutput', false);
        mask.PortRotation = 'default';
    end

    % Build display string (port labels)
    displayLines = {};
    for i = 1:numel(info.Inputs)
        name = strrep(char(info.Inputs(i).Name), "'", "''");
        displayLines{end+1} = sprintf("port_label('input',%d,'%s')", i, name); %#ok<AGROW>
    end
    for i = 1:numel(info.Outputs)
        name = strrep(char(info.Outputs(i).Name), "'", "''");
        displayLines{end+1} = sprintf("port_label('output',%d,'%s')", i, name); %#ok<AGROW>
    end
    if ~isempty(displayLines)
        mask.Display = strjoin(displayLines, newline);
    end
end

function unloadIfLoaded(alias)
    if libisloaded(char(alias))
        try
            unloadlibrary(char(alias));
        catch
        end
    end
end
