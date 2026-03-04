function cigreDLLSFunction(block)
% CIGREDRLLSFUNCTION  Level-2 MATLAB S-Function that executes a CIGRE DLL.
%
% This file is generated once and is shared by every CIGRE DLL block
% created by cigre.importDLL.  The DLL identity and tunable parameter
% values are stored as block dialog parameters (see Dialog Parameters
% section below).
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
%   setup()  – loads the DLL, calls Model_GetInfo(), configures input /
%              output ports and sample time, then unloads the DLL.
%   Start()  – reloads the DLL, packs parameters, creates an
%              InterfaceInstance, calls Model_FirstCall and
%              Model_Initialize, stores state in SimUserData.
%   Outputs()– packs input port data, calls Model_Outputs, unpacks
%              output port data.
%   Terminate() – calls Model_Terminate and unloads the DLL.

    setup(block);
end

% ======================================================================= %
%  setup – configure ports, sample time and callbacks
% ======================================================================= %
function setup(block)

    % The first two dialog params are always DLL path and header path.
    % Any additional params are CIGRE parameter values.
    block.NumDialogPrms = block.NumDialogPrms; % keep existing count

    dllPath    = string(block.DialogPrm(1).Data);
    headerPath = string(block.DialogPrm(2).Data);

    % ---- Load DLL temporarily to read model info ---- %
    alias = loadDLLForInfo(dllPath, headerPath);
    cleanupLib = onCleanup(@() unloadIfLoaded(alias));

    info = cigre.importer.ModelInfo.fromLoadedDLL(alias);

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

    % Load DLL for simulation (unique alias per block instance)
    alias = loadDLLForInfo(dllPath, headerPath);

    % Re-read model info to know types/widths
    info = cigre.importer.ModelInfo.fromLoadedDLL(alias);

    % Build initial zero inputs (correctly typed)
    inputs = buildZeroSignals(info.Inputs);

    % Build initial zero outputs (correctly typed)
    outputs = buildZeroSignals(info.Outputs);

    % Build parameters from dialog params 3..N+2
    parameters = buildParameters(block, info.Parameters);

    % Create InterfaceInstance (packs inputs/outputs/params into byte buffers)
    instance = cigre.dll.InterfaceInstance(inputs, outputs, parameters);

    % Create CigreDLL using the already-loaded alias
    dll = cigre.dll.CigreDLL(dllPath, 'Header', headerPath);
    dll.Name_  = alias;   % point at the already-loaded library
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

function alias = loadDLLForInfo(dllPath, headerPath)
% Load the DLL with a unique alias.  Returns the alias string.
    cigreSrc = fullfile(cigreRoot(), 'src', 'CIGRESource');
    alias    = "cigredll_" + matlab.lang.makeValidName(fileparts(dllPath)) ...
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
    slType = cigre.importer.ModelInfo.cigreTypeToSimulink(cigreDataType);
    typeMap = dictionary( ...
        ["double","single","int8","uint8","int16","uint16","int32","uint32"], ...
        [0, 1, 2, 3, 4, 5, 6, 7]);
    if typeMap.isKey(slType)
        id = typeMap(slType);
    else
        id = 0; % default to double
    end
end
