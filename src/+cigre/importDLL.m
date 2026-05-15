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
%   Harness      (logical) Add a default test harness around the
%                imported block: a Test Sequence (or Constant fallback)
%                driving 0 into each input, and one Outport per DLL
%                output. Default: true.
%
%   Overwrite    (logical) Permit overwriting an existing .slx at the
%                target path. Default: false - importDLL errors rather
%                than clobber a file, so it can never destroy a model
%                that happens to share the generated name.
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
        nvp.Harness (1,1) logical = true
        nvp.Overwrite (1,1) logical = false
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

    % Suffix the model so it can sit alongside the actual CIGRE block of
    % the same base name without colliding in the same folder.
    modelName = blockName + "_ImportedCIGREDLL";
    modelPath = string(fullfile(outputFolder, modelName + ".slx"));

    % Never silently overwrite an existing model file. The generated
    % name is derived from the DLL's own ModelName, so in principle it
    % could collide with a user's model; refuse rather than risk
    % destroying it. Overwrite=true opts back in (e.g. for a re-import).
    if isfile(modelPath) && ~nvp.Overwrite
        error("CIGRE:importDLL:ModelExists", ...
            "A file already exists at:\n  %s\n" + ...
            "importDLL will not overwrite it. Move or delete that file, " + ...
            "pass a different BlockName / OutputFolder, or call importDLL " + ...
            "with Overwrite=true to replace it deliberately.", modelPath);
    end

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

        if nvp.Harness
            addDefaultHarness(modelName, blockName, info);
        end

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


function addDefaultHarness(modelName, blockName, info)
% Wrap the imported DLL block with a runnable harness.
%
% Inputs are driven by a single Test Sequence block emitting 0 on each
% input (correctly typed and sized). If Simulink Test isn't licensed or
% the sltest API rejects the configuration, fall back to one
% Constant=0 block per input. Outputs get one Outport each, named
% <port>_out so the harness model is immediately simulatable.
arguments
    modelName (1,1) string
    blockName (1,1) string
    info (1,1) cigre.importer.ModelInfo
end

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
    sig = info.Outputs(i);
    outName = char(matlab.lang.makeValidName(string(sig.Name)) + "_out");
    outPath = [modelName '/' outName];

    y0 = 80 + 40 * (i - 1);
    add_block('built-in/Outport', outPath, ...
        'Position', mat2str([450, y0, 480, y0 + 14]));

    try
        dt = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
        set_param(outPath, 'OutDataTypeStr', dt);
    catch
        % OutDataTypeStr is fussy on some releases for enum-backed
        % types; leave the default rather than fail harness creation.
    end

    add_line(modelName, ...
        sprintf('%s/%d', blockName, i), ...
        sprintf('%s/1', outName), ...
        'autorouting', 'on');
end
end


function ok = addTestSequenceSource(modelName, blockName, inputs)
% Try to add a single Test Sequence block driving zeros on every input.
% Returns true on success; on any failure removes the partial block and
% returns false so the caller can fall back to Constants.
ok = false;
if ~license('test', 'Simulink_Test')
    return
end

tsName = 'TestSequence';
tsPath = [modelName '/' tsName];
nIn = numel(inputs);

height = max(120, 40 * nIn + 40);
try
    add_block('sltestlib/Test Sequence', tsPath, ...
        'Position', mat2str([-200, 80, -50, 80 + height]));
catch
    return
end

try
    % Documented sltest API. addSymbol signature is
    %   addSymbol(blockPath, name, kind, scope, 'Prop', val, ...)
    % - kind = 'Data', scope = 'Output' makes the symbol a block output
    %   port. No Step1 action is needed: an Output data symbol
    %   initialises to 0 of its declared type/size, which is exactly
    %   what the harness wants.
    for i = 1:nIn
        sig = inputs(i);
        sym = char(matlab.lang.makeValidName(string(sig.Name)));
        dt = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
        w = max(1, sig.Width);

        sltest.testsequence.addSymbol(tsPath, sym, 'Data', 'Output');
        sltest.testsequence.editSymbol(tsPath, sym, ...
            'DataType', dt, ...
            'Size', sprintf('[1 %d]', w));
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
% Fallback when Test Sequence isn't available: one Constant=0 block
% per input, correctly typed and sized.
for i = 1:numel(inputs)
    sig = inputs(i);
    srcName = char(matlab.lang.makeValidName(string(sig.Name)) + "_zero");
    srcPath = [modelName '/' srcName];
    dt = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
    w = max(1, sig.Width);

    y0 = 80 + 40 * (i - 1);
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
        % As in addDefaultHarness: tolerate releases that refuse the
        % set_param for enum-backed types.
    end

    add_line(modelName, ...
        sprintf('%s/1', srcName), ...
        sprintf('%s/%d', blockName, i), ...
        'autorouting', 'on');
end
end
