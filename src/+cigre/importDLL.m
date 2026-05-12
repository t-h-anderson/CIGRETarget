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
%   Harness      (logical) Add a default test harness around the imported
%                block: a Test Sequence (or Constant fallback) driving 0
%                into each input, and one Outport per DLL output.
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
        dllPath          (1,1) string
        nvp.Header       (1,1) string  = fullfile(cigreRoot, "src", "CIGRESource", "IEEE_Cigre_DLLInterface.h")
        nvp.OutputFolder (1,1) string  = string(pwd)
        nvp.BlockName    (1,1) string  = string(missing)
        nvp.OpenModel    (1,1) logical = true
        nvp.Harness      (1,1) logical = true
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
    %  Resolve header path (needed at simulation time by the S-Function)
    % ------------------------------------------------------------------ %
    if ismissing(nvp.Header)
        headerPath = fullfile(dllDir, dllBase + ".h");
    else
        headerPath = resolvePath(nvp.Header);
    end
    if ~isfile(headerPath)
        error('CIGRE:importDLL:HeaderNotFound', ...
            'DLL header not found: %s\nSpecify it explicitly via the Header argument.', ...
            headerPath);
    end

    % ------------------------------------------------------------------ %
    %  Read model info via MEX (DLL is not kept loaded)
    % ------------------------------------------------------------------ %
    info = cigre.importer.ModelInfo.fromDLL(dllPath);

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

    modelName = blockName + "_ImportedCIGREDLL";
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
        % ---- Add Level-2 MATLAB S-Function block ----
        % Try the modern library path; fall back to the older MATLAB name.
        addLevel2SFBlock(blockPath);

        % ---- Apply mask (defines mask workspace variables) ----
        % Returns the ordered list of mask parameter variable names.
        paramVarNames = applyMask(blockPath, info, dllPath, headerPath);

        % ---- Wire S-Function dialog params to mask variables ----
        % Simulink evaluates each variable name in the mask workspace and
        % passes the result as the corresponding block.DialogPrm(i):
        %   1 = DLLPath (char), 2 = HeaderPath (char), 3..N+2 = param values
        set_param(char(blockPath), 'Parameters', ...
            char(strjoin(paramVarNames, ', ')));

        % ---- Default harness (Test Sequence inputs, Outport outputs) ----
        if nvp.Harness
            addDefaultHarness(modelName, blockName, info);
        end

        % ---- Save ----
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

    fprintf('CIGRE DLL imported successfully.\n');
    fprintf('  Model      : %s  v%s\n', info.Name, info.Version);
    fprintf('  Inputs     : %d\n', numel(info.Inputs));
    fprintf('  Outputs    : %d\n', numel(info.Outputs));
    fprintf('  Parameters : %d\n', numel(info.Parameters));
    fprintf('  Saved to   : %s\n', modelPath);
end

% ======================================================================= %
%  Local helpers
% ======================================================================= %

function p = resolvePath(p)
    resolved = which(p);
    if ~isempty(resolved)
        p = string(resolved);
    else
        p = string(p);
    end
end

function addLevel2SFBlock(blockPath)
% Add a Level-2 MATLAB S-Function block, handling name differences across
% MATLAB versions.
    names = { ...
        'simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
        'simulink/User-Defined Functions/Level-2 M-file S-Function'};
    added = false;
    for k = 1:numel(names)
        try
            add_block(names{k}, char(blockPath), ...
                'FunctionName', 'cigreDLLSFunction', ...
                'Position',     [100, 100, 300, 200]);
            added = true;
            break
        catch
        end
    end
    if ~added
        error('CIGRE:importDLL:BlockNotFound', ...
            ['Could not add a Level-2 MATLAB S-Function block. ' ...
             'Check that Simulink is installed.']);
    end
end

function paramVarNames = applyMask(blockPath, info, dllPath, headerPath)
% Create a Simulink mask on blockPath.
%
% Adds:
%   - Hidden 'DLLPath' and 'HeaderPath' parameters so the S-Function can
%     reload the library at simulation time via loadlibrary.
%   - One visible edit parameter per CIGRE DLL parameter.
%
% Returns paramVarNames: a string array of mask variable names in order
% [DLLPath, HeaderPath, p1, p2, ...] used to build the S-Function
% 'Parameters' string.

    mask = Simulink.Mask.create(char(blockPath));

    % Description panel
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

    % Helper: escape single quotes in a path for use inside a MATLAB
    % string literal (e.g.  'C:\it''s\dll.dll')
    escapePath = @(p) char("'" + strrep(string(p), "'", "''") + "'");

    % ---- Hidden path parameters ---- %
    pDLL = mask.addParameter('Type', 'edit', ...
        'Name',    'DLLPath', ...
        'Prompt',  'DLL file path', ...
        'Value',   escapePath(dllPath), ...
        'Tunable', 'off');
    pDLL.Visible = 'off';

    pHdr = mask.addParameter('Type', 'edit', ...
        'Name',    'HeaderPath', ...
        'Prompt',  'Header file path', ...
        'Value',   escapePath(headerPath), ...
        'Tunable', 'off');
    pHdr.Visible = 'off';

    paramVarNames = ["DLLPath", "HeaderPath"];

    % ---- One visible parameter per CIGRE DLL parameter ---- %
    for i = 1:numel(info.Parameters)
        p   = info.Parameters(i);
        vid = matlab.lang.makeValidName(string(p.Name));

        % Guarantee uniqueness across accumulated variable names
        vid = matlab.lang.makeUniqueStrings(vid, paramVarNames);

        % Prompt label with optional unit
        prompt = string(p.Name);
        unit   = strtrim(string(p.Unit));
        if unit ~= ""
            prompt = prompt + " [" + unit + "]";
        end

        mp = mask.addParameter('Type',    'edit', ...
            'Name',    char(vid), ...
            'Prompt',  char(prompt), ...
            'Value',   mat2str(p.DefaultValue), ...
            'Tunable', 'on');

        desc = strtrim(string(p.Description));
        if desc ~= ""
            try
                mp.Tooltip = char(desc);
            catch
            end
        end

        grp = strtrim(string(p.GroupName));
        if grp ~= ""
            try
                mp.GroupName = char(grp);
            catch
            end
        end

        paramVarNames(end+1) = vid; %#ok<AGROW>
    end

    % ---- Port labels on block icon ---- %
    displayLines = string.empty(1,0);
    for i = 1:numel(info.Inputs)
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

% ======================================================================= %
%  Default harness
% ======================================================================= %

function addDefaultHarness(modelName, blockName, info)
% Add a default harness around the imported DLL block.
%
%   Inputs : a single Test Sequence block emitting 0 on each input
%            (correctly typed and sized).  If Simulink Test isn't licensed
%            or configuration fails, fall back to one Constant=0 block per
%            input.
%   Outputs: one Outport per DLL output, named after the port.

    modelName = char(modelName);
    blockName = char(blockName);

    if numel(info.Inputs) > 0
        added = false;
        try
            added = addTestSequenceSource(modelName, blockName, info.Inputs);
        catch
            added = false;
        end
        if ~added
            addConstantSources(modelName, blockName, info.Inputs);
        end
    end

    for i = 1:numel(info.Outputs)
        sig     = info.Outputs(i);
        outName = char(matlab.lang.makeValidName(string(sig.Name)) + "_out");
        outPath = [modelName '/' outName];

        y0 = 80 + 40*(i - 1);
        add_block('built-in/Outport', outPath, ...
            'Position', mat2str([450, y0, 480, y0 + 14]));

        try
            dt = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
            set_param(outPath, 'OutDataTypeStr', dt);
        catch
        end

        add_line(modelName, ...
            sprintf('%s/%d', blockName, i), ...
            sprintf('%s/1', outName), ...
            'autorouting', 'on');
    end
end

function ok = addTestSequenceSource(modelName, blockName, inputs)
% Try to add and configure a single Test Sequence block driving zeros.
% On any failure, remove the partially-built block and return false so the
% caller can fall back to Constants.
    ok = false;
    if ~license('test', 'Simulink_Test')
        return
    end

    tsName = 'TestSequence';
    tsPath = [modelName '/' tsName];
    nIn    = numel(inputs);

    height = max(120, 40 * nIn + 40);
    try
        add_block('sltestlib/Test Sequence', tsPath, ...
            'Position', mat2str([-200, 80, -50, 80 + height]));
    catch
        return
    end

    try
        % The sltest.testsequence.addSymbol/editSymbol API has been brittle
        % across releases and naming conventions; talk to the underlying
        % Stateflow chart directly, which is the stable lower-level API.
        chart = sfroot.find('Path', tsPath, '-isa', 'Stateflow.Chart');
        if isempty(chart)
            error('CIGRE:NoChart', ...
                'Could not locate Stateflow chart for Test Sequence at %s.', tsPath);
        end

        actionLines = strings(0,1);
        for i = 1:nIn
            sig = inputs(i);
            sym = char(matlab.lang.makeValidName(string(sig.Name)));
            dt  = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
            w   = max(1, sig.Width);

            d = Stateflow.Data(chart);
            d.Name     = sym;
            d.Scope    = 'Output';
            d.DataType = dt;
            if w > 1
                d.Props.Array.Size = sprintf('[1 %d]', w);
            end

            if w == 1
                actionLines(end+1) = string(sym) + " = " + string(dt) + "(0);"; %#ok<AGROW>
            else
                actionLines(end+1) = string(sym) + " = zeros(1, " + w + ", '" + string(dt) + "');"; %#ok<AGROW>
            end
        end

        action = char(strjoin(actionLines, newline));
        try
            sltest.testsequence.editStep(tsPath, 'Step1', 'Action', action);
        catch
            sltest.testsequence.addStep(tsPath, 'Step1', 'Action', action);
        end

        for i = 1:nIn
            add_line(modelName, ...
                sprintf('%s/%d', tsName, i), ...
                sprintf('%s/%d', blockName, i), ...
                'autorouting', 'on');
        end

        ok = true;
    catch
        try
            delete_block(tsPath);
        catch
        end
    end
end

function addConstantSources(modelName, blockName, inputs)
% Fallback: one Constant=0 block per input, correctly typed and sized.
    for i = 1:numel(inputs)
        sig     = inputs(i);
        srcName = char(matlab.lang.makeValidName(string(sig.Name)) + "_zero");
        srcPath = [modelName '/' srcName];
        dt      = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
        w       = max(1, sig.Width);

        y0 = 80 + 40*(i - 1);
        add_block('built-in/Constant', srcPath, ...
            'Position', mat2str([-180, y0, -80, y0 + 30]));

        if w == 1
            valStr = '0';
        else
            valStr = sprintf('zeros(1, %d)', w);
        end
        set_param(srcPath, 'Value', valStr);
        try
            set_param(srcPath, 'OutDataTypeStr', dt);
        catch
        end

        add_line(modelName, ...
            sprintf('%s/1', srcName), ...
            sprintf('%s/%d', blockName, i), ...
            'autorouting', 'on');
    end
end
