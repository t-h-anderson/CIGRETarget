function cigreDLLSFunction(block)
arguments
    block (1,1)
end
% CIGREDLLSFUNCTION  Level-2 MATLAB S-Function that executes a CIGRE DLL.
%
% This file is shared by every CIGRE DLL block created by cigre.importDLL.
% The DLL identity and tunable parameter values are stored as block dialog
% parameters (see Dialog Parameters below).
%
% Dialog Parameters
% -----------------
%   1  DLLPath     (char) - absolute path to the CIGRE DLL (.dll)
%   2  HeaderPath  (char) - absolute path to the DLL header file (.h)
%   3..N+2         (double) - one value per CIGRE parameter, in the
%                  order returned by Model_GetInfo().ParametersInfo.
%
% Simulation Phases
% -----------------
%   setup()     - reads model info via the cigre_read_model_info MEX
%                 (no loadlibrary required here), then configures input /
%                 output ports and sample time.
%   Start()     - loads the DLL via loadlibrary, creates an
%                 InterfaceInstance, calls Model_FirstCall and
%                 Model_Initialize, stores state in UserData.
%   Outputs()   - packs input port data, calls Model_Outputs, unpacks
%                 output port data.
%   Terminate() - calls Model_Terminate and unloads the DLL.

    setup(block);
end

function setup(block)
arguments
    block (1,1)
end

    % Level-2 S-Functions must set block.NumDialogPrms before accessing any
    % block.DialogPrm(i). The count is variable (2 fixed paths + one per
    % CIGRE parameter), so the DLL path is read out of the mask workspace
    % first to discover it.
    %
    % On the initial add_block call (inside importDLL) the mask does not
    % exist yet and tryReadDLLPathFromMask returns "". Configure minimal
    % defaults and return early; importDLL then applies the mask and calls
    % set_param("Parameters", ...), which triggers a second setup() call
    % where the mask workspace is populated and the full configuration
    % proceeds.
    dllPath = tryReadDLLPathFromMask(block);
    if dllPath == ""
        block.NumDialogPrms = 0;
        block.NumInputPorts = 0;
        block.NumOutputPorts = 0;
        block.SampleTimes = [-1, 0];
        block.RegBlockMethod("Start", @Start);
        block.RegBlockMethod("Outputs", @Outputs);
        block.RegBlockMethod("Terminate", @Terminate);
        block.RegBlockMethod("CheckParameters", @CheckParameters);
        block.RegBlockMethod("ProcessParameters", @ProcessParameters);
        return
    end

    info = cigre.importer.ModelInfo.fromDLL(dllPath);

    block.NumDialogPrms = 2 + numel(info.Parameters);

    if info.SampleTime > 0
        block.SampleTimes = [info.SampleTime, 0];
    else
        block.SampleTimes = [-1, 0];
    end

    block.NumInputPorts = numel(info.Inputs);
    for i = 1:numel(info.Inputs)
        sig = info.Inputs(i);
        w = max(1, sig.Width);
        block.InputPort(i).Dimensions = w;
        block.InputPort(i).DatatypeID = cigreTypeToSimulinkID(sig.DataType);
        block.InputPort(i).Complexity = "Real";
        block.InputPort(i).DirectFeedthrough = true;
    end

    block.NumOutputPorts = numel(info.Outputs);
    for i = 1:numel(info.Outputs)
        sig = info.Outputs(i);
        w = max(1, sig.Width);
        block.OutputPort(i).Dimensions = w;
        block.OutputPort(i).DatatypeID = cigreTypeToSimulinkID(sig.DataType);
        block.OutputPort(i).Complexity = "Real";
    end

    block.RegBlockMethod("Start", @Start);
    block.RegBlockMethod("Outputs", @Outputs);
    block.RegBlockMethod("Terminate", @Terminate);
    block.RegBlockMethod("CheckParameters", @CheckParameters);
    block.RegBlockMethod("ProcessParameters", @ProcessParameters);
end

function CheckParameters(block) %#ok<DEFNU>
arguments
    block (1,1)
end
    % NumDialogPrms is 0 during the first setup() pass before the mask is
    % applied; nothing to check at that point.
    if block.NumDialogPrms < 2
        return
    end
    if ~isfile(string(block.DialogPrm(1).Data))
        error("CIGRE:cigreDLLSFunction:DLLNotFound", ...
            "CIGRE DLL not found: %s", block.DialogPrm(1).Data);
    end
    if ~isfile(string(block.DialogPrm(2).Data))
        error("CIGRE:cigreDLLSFunction:HeaderNotFound", ...
            "CIGRE DLL header not found: %s", block.DialogPrm(2).Data);
    end
end

function ProcessParameters(block) %#ok<DEFNU>
arguments
    block (1,1)
end
    block.AutoUpdateRuntimePrms();
end

function Start(block)
arguments
    block (1,1)
end

    dllPath = string(block.DialogPrm(1).Data);
    headerPath = string(block.DialogPrm(2).Data);

    info = cigre.importer.ModelInfo.fromDLL(dllPath);

    alias = loadDLLForSim(dllPath, headerPath);

    inputs = buildZeroSignals(info.Inputs);
    outputs = buildZeroSignals(info.Outputs);

    parameters = buildParameters(block, info.Parameters);

    instance = cigre.dll.InterfaceInstance(inputs, outputs, parameters);

    % CigreDLL would normally call loadlibrary itself; here the library
    % is already loaded under a unique alias so the handle is plugged in
    % directly to avoid a second load.
    dll = cigre.dll.CigreDLL(dllPath, "Header", headerPath);
    dll.Name_ = alias;
    dll.IsLoaded = true;

    dll.firstCall(instance);
    calllib(char(alias), "Model_CheckParameters", instance.Instance);
    dll.initialise(instance);

    userData.dll = dll;
    userData.instance = instance;
    userData.info = info;
    set_param(block.BlockHandle, "UserData", userData)
end

function Outputs(block)
arguments
    block (1,1)
end

    userData = get_param(block.BlockHandle, "UserData");
    instance = userData.instance;
    dll = userData.dll;
    info = userData.info;

    inputs = cell(1, numel(info.Inputs));
    for i = 1:numel(info.Inputs)
        inputs{i} = block.InputPort(i).Data;
    end
    instance.updateInputs(inputs);

    results = dll.step(instance);

    for i = 1:numel(info.Outputs)
        if i <= numel(results)
            block.OutputPort(i).Data = castToPort(results{i}, block.OutputPort(i).DatatypeID);
        end
    end
end

function Terminate(block)
arguments
    block (1,1)
end

    userData = get_param(block.BlockHandle, "UserData");
    if isempty(userData)
        return
    end
    dll = userData.dll;
    instance = userData.instance;

    try
        calllib(char(dll.Name_), "Model_Terminate", instance.Instance);
    catch
        % Non-fatal: the DLL may have already been unloaded by another
        % path (e.g. a previous failed Start), in which case calllib
        % throws but there is nothing useful to do.
    end

    dll.unload();
    set_param(block.BlockHandle, "UserData", userData);
end

function dllPath = tryReadDLLPathFromMask(block)
arguments
    block (1,1)
end
% Read the DLLPath value from the block's mask workspace.
% Returns "" if the mask does not exist yet or DLLPath is not defined.
    dllPath = "";
    try
        maskVars = get_param(block.BlockHandle, "MaskWSVariables");
        if isempty(maskVars), return; end
        idx = string({maskVars.Name}) == "DLLPath";
        if ~any(idx), return; end
        val = maskVars(idx).Value;
        if ~isempty(val)
            dllPath = string(val);
        end
    catch
    end
end

function alias = loadDLLForSim(dllPath, headerPath)
arguments
    dllPath (1,1) string
    headerPath (1,1) string
end
% MATLAB's loadlibrary parser (and the MinGW thunk compiler) reject the
% Windows annotations (__declspec, __cdecl, __stdcall, __attribute__) used
% in the IEEE/Cigre header on some releases (notably R2023b).
% sanitiseLoadlibraryHeader emits a wrapper that #define's those tokens
% to nothing before including the real header.
    cigreSrc = fullfile(cigreRoot(), "src", "CIGRESource");
    [~, base] = fileparts(dllPath);
    alias = "cigredll_" + matlab.lang.makeValidName(base) ...
            + "_" + cigre.util.uuid();
    unloadIfLoaded(alias);

    [wrapperHeader, headerDir] = cigre.util.sanitiseLoadlibraryHeader(headerPath);

    [~, notfound] = loadlibrary(char(dllPath), char(wrapperHeader), ...
        "includepath", cigreSrc, ...
        "includepath", headerDir, ...
        "alias", char(alias));

    % loadlibrary can return success on releases where the header parser
    % bailed mid-file; verify the Model_* prototypes registered so the
    % failure is reported here rather than as "Type was not found" deep
    % inside libpointer during simulation.
    cigre.util.assertCigreLibraryLoaded(alias, notfound);
end

function unloadIfLoaded(alias)
arguments
    alias (1,1) string
end
    if libisloaded(char(alias))
        try
            unloadlibrary(char(alias));
        catch
        end
    end
end

function signals = buildZeroSignals(sigInfoArray)
arguments
    sigInfoArray (1,:) struct
end
% Build a cell array of zero-valued typed arrays, one per signal descriptor.
    signals = cell(1, numel(sigInfoArray));
    for i = 1:numel(sigInfoArray)
        sig = sigInfoArray(i);
        matlabType = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
        w = max(1, sig.Width);
        signals{i} = zeros(1, w, matlabType);
    end
end

function parameters = buildParameters(block, paramInfoArray)
arguments
    block (1,1)
    paramInfoArray (1,:) struct
end
% Build a struct array with .Value fields for InterfaceInstance.
% Values come from dialog parameters 3..N+2; defaults are used if absent.
    n = numel(paramInfoArray);
    parameters = struct("Value", cell(1, n));
    for i = 1:n
        pi = paramInfoArray(i);
        matlabType = char(cigre.importer.ModelInfo.cigreTypeToSimulink(pi.DataType));
        dialogIdx = i + 2;
        if dialogIdx <= block.NumDialogPrms
            val = double(block.DialogPrm(dialogIdx).Data);
        else
            val = pi.DefaultValue;
        end
        parameters(i).Value = cast(val, matlabType);
    end
end

function out = castToPort(data, datatypeID)
arguments
    data
    datatypeID (1,1) double
end
% Cast data to the MATLAB type matching a Simulink DatatypeID.
    typeNames = ["double", "single", "int8", "uint8", "int16", "uint16", "int32", "uint32", "logical"];
    if datatypeID >= 0 && datatypeID < numel(typeNames)
        out = cast(data, typeNames(datatypeID + 1));
    else
        out = data;
    end
end

function id = cigreTypeToSimulinkID(cigreDataType)
arguments
    cigreDataType (1,1) double
end
% Map CIGRE DataType enum value to Simulink DatatypeID (integer).
%   double=0, single=1, int8=2, uint8=3, int16=4, uint16=5, int32=6, uint32=7
    slType = string(cigre.importer.ModelInfo.cigreTypeToSimulink(cigreDataType));
    switch slType
        case "double", id = 0;
        case "single", id = 1;
        case "int8", id = 2;
        case "uint8", id = 3;
        case "int16", id = 4;
        case "uint16", id = 5;
        case "int32", id = 6;
        case "uint32", id = 7;
        otherwise, id = 0;
    end
end
