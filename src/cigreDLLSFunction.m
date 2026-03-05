function cigreDLLSFunction(block)
% CIGREDRLLSFUNCTION  Level-2 MATLAB S-Function that executes a CIGRE DLL.
%
% This file is shared by every CIGRE DLL block created by cigre.importDLL.
% The DLL identity and tunable parameter values are stored as block dialog
% parameters (see Dialog Parameters below).
%
% Dialog Parameters
% -----------------
%   1  DLLPath     (char) – absolute path to the CIGRE DLL (.dll)
%   2  HeaderPath  (char) – absolute path to the DLL header file (.h)
%   3..N+2         (double) – one value per CIGRE parameter, in the
%                  order returned by Model_GetInfo().ParametersInfo.
%
% Simulation Phases
% -----------------
%   setup()     – reads model info via the cigre_read_model_info MEX
%                 (no loadlibrary required here), then configures input /
%                 output ports and sample time.
%   Start()     – loads the DLL via loadlibrary, creates an
%                 InterfaceInstance, calls Model_FirstCall and
%                 Model_Initialize, stores state in UserData.
%   Outputs()   – packs input port data, calls Model_Outputs, unpacks
%                 output port data.
%   Terminate() – calls Model_Terminate and unloads the DLL.

    setup(block);
end

% ======================================================================= %
%  setup – configure ports, sample time and callbacks
% ======================================================================= %
function setup(block)

    % Level-2 S-Functions must set block.NumDialogPrms before accessing any
    % block.DialogPrm(i).  Our count is variable (2 fixed paths plus one per
    % CIGRE parameter), so we read the DLL path from the mask workspace —
    % available immediately via get_param, before the parameter count is
    % declared — call fromDLL() to learn how many CIGRE parameters there are,
    % then declare the total count.
    dllPath = readDLLPathFromMask(block);

    % Read model info via MEX — no loadlibrary required in setup.
    info = cigre.importer.ModelInfo.fromDLL(dllPath);

    % Declare parameter count: 2 fixed (DLLPath, HeaderPath) + one per param.
    block.NumDialogPrms = 2 + numel(info.Parameters);

    % ---- Configure sample time ---- %
    if info.SampleTime > 0
        block.SampleTimes = [info.SampleTime, 0];
    else
        % Inherited sample time as fallback
        block.SampleTimes = [-1, 0];
    end

    % ---- Input ports ---- %
    block.NumInputPorts = numel(info.Inputs);
    for i = 1:numel(info.Inputs)
        sig = info.Inputs(i);
        w   = max(1, sig.Width);
        block.InputPort(i).Dimensions  = w;
        block.InputPort(i).DatatypeID  = cigreTypeToSimulinkID(sig.DataType);
        block.InputPort(i).Complexity  = 'Real';
        block.InputPort(i).DirectFeedthrough = true;
    end

    % ---- Output ports ---- %
    block.NumOutputPorts = numel(info.Outputs);
    for i = 1:numel(info.Outputs)
        sig = info.Outputs(i);
        w   = max(1, sig.Width);
        block.OutputPort(i).Dimensions = w;
        block.OutputPort(i).DatatypeID = cigreTypeToSimulinkID(sig.DataType);
        block.OutputPort(i).Complexity = 'Real';
    end

    % ---- Register callbacks ---- %
    block.RegBlockMethod('Start',                @Start);
    block.RegBlockMethod('Outputs',              @Outputs);
    block.RegBlockMethod('Terminate',            @Terminate);
    block.RegBlockMethod('CheckParameters',      @CheckParameters);
    block.RegBlockMethod('ProcessParameters',    @ProcessParameters);
end

% ======================================================================= %
%  CheckParameters / ProcessParameters
% ======================================================================= %
function CheckParameters(block) %#ok<DEFNU>
    if block.NumDialogPrms < 2
        error('CIGRE:cigreDLLSFunction:BadParams', ...
            'Block requires at least 2 dialog parameters (DLLPath, HeaderPath).');
    end
    if ~isfile(string(block.DialogPrm(1).Data))
        error('CIGRE:cigreDLLSFunction:DLLNotFound', ...
            'CIGRE DLL not found: %s', block.DialogPrm(1).Data);
    end
    if ~isfile(string(block.DialogPrm(2).Data))
        error('CIGRE:cigreDLLSFunction:HeaderNotFound', ...
            'CIGRE DLL header not found: %s', block.DialogPrm(2).Data);
    end
end

function ProcessParameters(block) %#ok<DEFNU>
    block.AutoUpdateRuntimePrms();
end

% ======================================================================= %
%  Start – load DLL, allocate instance, run initialisation
% ======================================================================= %
function Start(block)

    dllPath    = string(block.DialogPrm(1).Data);
    headerPath = string(block.DialogPrm(2).Data);

    % Read model info (MEX, no loadlibrary needed)
    info = cigre.importer.ModelInfo.fromDLL(dllPath);

    % Load DLL for simulation via loadlibrary with a unique alias
    alias = loadDLLForSim(dllPath, headerPath);

    % Build initial zero inputs/outputs (correctly typed)
    inputs  = buildZeroSignals(info.Inputs);
    outputs = buildZeroSignals(info.Outputs);

    % Build parameters from dialog params 3..N+2
    parameters = buildParameters(block, info.Parameters);

    % Create InterfaceInstance (packs inputs/outputs/params into byte buffers)
    instance = cigre.dll.InterfaceInstance(inputs, outputs, parameters);

    % Wrap in CigreDLL pointing at the already-loaded alias
    dll = cigre.dll.CigreDLL(dllPath, 'Header', headerPath);
    dll.Name_    = alias;
    dll.IsLoaded = true;

    % Lifecycle calls
    dll.firstCall(instance);
    calllib(char(alias), 'Model_CheckParameters', instance.Instance);
    dll.initialise(instance);

    % Store state for Outputs / Terminate
    userData.dll      = dll;
    userData.instance = instance;
    userData.info     = info;
    block.UserData    = userData;
end

% ======================================================================= %
%  Outputs – pack inputs, step DLL, unpack outputs
% ======================================================================= %
function Outputs(block)

    userData = block.UserData;
    instance = userData.instance;
    dll      = userData.dll;
    info     = userData.info;

    % Pack current Simulink input port values into the interface buffers
    inputs = cell(1, numel(info.Inputs));
    for i = 1:numel(info.Inputs)
        inputs{i} = block.InputPort(i).Data;
    end
    instance.updateInputs(inputs);

    % Advance the DLL model by one step
    results = dll.step(instance);

    % Write DLL outputs to Simulink output ports
    for i = 1:numel(info.Outputs)
        if i <= numel(results)
            block.OutputPort(i).Data = castToPort(results{i}, block.OutputPort(i).DatatypeID);
        end
    end
end

% ======================================================================= %
%  Terminate – clean shutdown
% ======================================================================= %
function Terminate(block)

    userData = block.UserData;
    if isempty(userData)
        return
    end
    dll      = userData.dll;
    instance = userData.instance;

    try
        calllib(char(dll.Name_), 'Model_Terminate', instance.Instance);
    catch
        % Non-fatal: DLL may already be gone
    end

    dll.unload();
    block.UserData = [];
end

% ======================================================================= %
%  Helper functions
% ======================================================================= %

function dllPath = readDLLPathFromMask(block)
% Read the DLLPath value from the block's mask workspace.
% Used in setup() before NumDialogPrms is declared.
    bh       = block.BlockHandle;
    maskVars = get_param(bh, 'MaskWSVariables');
    idx      = strcmp({maskVars.Name}, 'DLLPath');
    if ~any(idx)
        error('CIGRE:cigreDLLSFunction:NoDLLPath', ...
            'Block mask does not define a DLLPath variable. ' ...
            'Create the block with cigre.importDLL().');
    end
    dllPath = string(maskVars(idx).Value);
end

function alias = loadDLLForSim(dllPath, headerPath)
% Load the CIGRE DLL for simulation via loadlibrary.
% Returns the unique library alias string.
    cigreSrc = fullfile(cigreRoot(), 'src', 'CIGRESource');
    [~, base] = fileparts(dllPath);
    alias = "cigredll_" + matlab.lang.makeValidName(base) ...
            + "_" + cigre.util.uuid();
    unloadIfLoaded(alias);
    loadlibrary(char(dllPath), char(headerPath), ...
        'includepath', cigreSrc, ...
        'alias',       char(alias));
end

function unloadIfLoaded(alias)
    if libisloaded(char(alias))
        try
            unloadlibrary(char(alias));
        catch
        end
    end
end

function signals = buildZeroSignals(sigInfoArray)
% Build a cell array of zero-valued typed arrays, one per signal descriptor.
    signals = cell(1, numel(sigInfoArray));
    for i = 1:numel(sigInfoArray)
        sig       = sigInfoArray(i);
        matlabType = char(cigre.importer.ModelInfo.cigreTypeToSimulink(sig.DataType));
        w         = max(1, sig.Width);
        signals{i} = zeros(1, w, matlabType);
    end
end

function parameters = buildParameters(block, paramInfoArray)
% Build a struct array with .Value fields for InterfaceInstance.
% Values come from dialog parameters 3..N+2; defaults are used if absent.
    n = numel(paramInfoArray);
    parameters = struct('Value', cell(1, n));
    for i = 1:n
        pi = paramInfoArray(i);
        matlabType = char(cigre.importer.ModelInfo.cigreTypeToSimulink(pi.DataType));
        dialogIdx  = i + 2;
        if dialogIdx <= block.NumDialogPrms
            val = double(block.DialogPrm(dialogIdx).Data);
        else
            val = pi.DefaultValue;
        end
        parameters(i).Value = cast(val, matlabType);
    end
end

function out = castToPort(data, datatypeID)
% Cast data to the MATLAB type matching a Simulink DatatypeID.
    typeNames = {'double','single','int8','uint8','int16','uint16','int32','uint32','logical'};
    if datatypeID >= 0 && datatypeID < numel(typeNames)
        out = cast(data, typeNames{datatypeID + 1});
    else
        out = data;
    end
end

function id = cigreTypeToSimulinkID(cigreDataType)
% Map CIGRE DataType enum value to Simulink DatatypeID (integer).
%   double=0, single=1, int8=2, uint8=3, int16=4, uint16=5, int32=6, uint32=7
    slType = char(cigre.importer.ModelInfo.cigreTypeToSimulink(cigreDataType));
    switch slType
        case 'double',  id = 0;
        case 'single',  id = 1;
        case 'int8',    id = 2;
        case 'uint8',   id = 3;
        case 'int16',   id = 4;
        case 'uint16',  id = 5;
        case 'int32',   id = 6;
        case 'uint32',  id = 7;
        otherwise,      id = 0;
    end
end
