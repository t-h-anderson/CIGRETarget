classdef ModelInfo
% MODELINFO  Parsed metadata read from a CIGRE-compliant DLL via Model_GetInfo().
%
% After calling cigre.importDLL (or cigre.importer.ModelInfo.fromLoadedDLL)
% you receive a ModelInfo object whose fields mirror the
% IEEE_Cigre_DLLInterface_Model_Info C struct:
%
%   Name        - ModelName string
%   Version     - ModelVersion string
%   Description - ModelDescription string
%   SampleTime  - FixedStepBaseSampleTime (seconds)
%   EMT_RMS_Mode - 1=EMT, 2=RMS, 3=both
%   Inputs      - (1xN) struct array of signal descriptors
%   Outputs     - (1xM) struct array of signal descriptors
%   Parameters  - (1xP) struct array of parameter descriptors
%
% Signal struct fields   : Name, Description, Unit, DataType (int), Width
% Parameter struct fields: Name, GroupName, Description, Unit, DataType,
%                          FixedValue, DefaultValue, MinValue, MaxValue

    properties
        Name        (1,1) string = ""
        Version     (1,1) string = ""
        Description (1,1) string = ""
        SampleTime  (1,1) double = 0
        EMT_RMS_Mode (1,1) uint8 = 1
        % Signal struct arrays (fields: Name, Description, Unit, DataType, Width)
        Inputs      (1,:) struct
        Outputs     (1,:) struct
        % Parameter struct array (fields: Name, GroupName, Description,
        %   Unit, DataType, FixedValue, DefaultValue, MinValue, MaxValue)
        Parameters  (1,:) struct
    end

    % ------------------------------------------------------------------ %
    methods (Static)

        function info = fromLoadedDLL(alias)
        % FROMLOADEDDLL  Read ModelInfo from a DLL already loaded by loadlibrary.
        %
        %   info = cigre.importer.ModelInfo.fromLoadedDLL(alias)
        %
        %   alias - library alias string used in the loadlibrary call.
        %
        % Calls the DLL's Model_GetInfo() entry-point and parses the
        % returned IEEE_Cigre_DLLInterface_Model_Info struct into a
        % ModelInfo object.

            info = cigre.importer.ModelInfo();

            infoPtr = calllib(char(alias), 'Model_GetInfo');
            if isNull(infoPtr)
                error('CIGRE:ModelInfo:NullInfo', ...
                    'Model_GetInfo() returned a null pointer.');
            end

            modelInfo = infoPtr.Value;

            info.Name        = cigre.importer.ModelInfo.readCString(modelInfo.ModelName);
            info.Version     = cigre.importer.ModelInfo.readCString(modelInfo.ModelVersion);
            info.Description = cigre.importer.ModelInfo.readCString(modelInfo.ModelDescription);
            info.SampleTime  = double(modelInfo.FixedStepBaseSampleTime);
            info.EMT_RMS_Mode = uint8(modelInfo.EMT_RMS_Mode);

            numIn    = double(modelInfo.NumInputPorts);
            numOut   = double(modelInfo.NumOutputPorts);
            numParam = double(modelInfo.NumParameters);

            info.Inputs     = cigre.importer.ModelInfo.readSignalArray( ...
                                  modelInfo.InputPortsInfo,  numIn);
            info.Outputs    = cigre.importer.ModelInfo.readSignalArray( ...
                                  modelInfo.OutputPortsInfo, numOut);
            info.Parameters = cigre.importer.ModelInfo.readParameterArray( ...
                                  modelInfo.ParametersInfo,  numParam);
        end

        function slType = cigreTypeToSimulink(cigreDataType)
        % CIGRETYPETOSIMULNK  Map a CIGRE DataType enum integer to a
        % Simulink type name string.
        %
        %   slType = cigre.importer.ModelInfo.cigreTypeToSimulink(cigreDataType)
        %
        % Mapping based on IEEE_Cigre_DLLInterface_types.h:
        %   1 char_T    -> 'int8'
        %   2 int8_T    -> 'int8'
        %   3 uint8_T   -> 'uint8'
        %   4 int16_T   -> 'int16'
        %   5 uint16_T  -> 'uint16'
        %   6 int32_T   -> 'int32'
        %   7 uint32_T  -> 'uint32'
        %   8 real32_T  -> 'single'
        %   9 real64_T  -> 'double'
        %  10 c_string_T -> 'int8'  (char array)

            persistent typeMap
            if isempty(typeMap)
                typeMap = [ ...
                    1,  "int8";   % char_T
                    2,  "int8";   % int8_T
                    3,  "uint8";  % uint8_T
                    4,  "int16";  % int16_T
                    5,  "uint16"; % uint16_T
                    6,  "int32";  % int32_T
                    7,  "uint32"; % uint32_T
                    8,  "single"; % real32_T
                    9,  "double"; % real64_T
                    10, "int8";   % c_string_T (char array)
                ];
            end

            keys = double(typeMap(:,1));
            idx  = find(keys == double(cigreDataType), 1);
            if isempty(idx)
                error('CIGRE:ModelInfo:UnknownType', ...
                    'Unknown CIGRE DataType enum value: %d', cigreDataType);
            end
            slType = typeMap(idx, 2);
        end

    end % public static methods

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function signals = readSignalArray(ptr, n)
        % Read n IEEE_Cigre_DLLInterface_Signal structs from a C array pointer.
            signals = struct('Name', {}, 'Description', {}, ...
                             'Unit', {}, 'DataType', {}, 'Width', {});
            if n <= 0 || isempty(ptr)
                return
            end
            try
                setdatatype(ptr, 's_IEEE_Cigre_DLLInterface_SignalPtr', 1, n);
                for i = 1:n
                    sig = ptr(i).Value;
                    signals(i).Name        = cigre.importer.ModelInfo.readCString(sig.Name);
                    signals(i).Description = cigre.importer.ModelInfo.readCString(sig.Description);
                    signals(i).Unit        = cigre.importer.ModelInfo.readCString(sig.Unit);
                    signals(i).DataType    = double(sig.DataType);
                    signals(i).Width       = double(sig.Width);
                end
            catch ME
                warning('CIGRE:ModelInfo:SignalReadFailed', ...
                    'Failed to read signal array: %s', ME.message);
            end
        end

        function params = readParameterArray(ptr, n)
        % Read n IEEE_Cigre_DLLInterface_Parameter structs from a C array pointer.
            params = struct('Name', {}, 'GroupName', {}, 'Description', {}, ...
                            'Unit', {}, 'DataType', {}, 'FixedValue', {}, ...
                            'DefaultValue', {}, 'MinValue', {}, 'MaxValue', {});
            if n <= 0 || isempty(ptr)
                return
            end
            try
                setdatatype(ptr, 's_IEEE_Cigre_DLLInterface_ParameterPtr', 1, n);
                for i = 1:n
                    p = ptr(i).Value;
                    params(i).Name        = cigre.importer.ModelInfo.readCString(p.Name);
                    params(i).GroupName   = cigre.importer.ModelInfo.readCString(p.GroupName);
                    params(i).Description = cigre.importer.ModelInfo.readCString(p.Description);
                    params(i).Unit        = cigre.importer.ModelInfo.readCString(p.Unit);
                    params(i).DataType    = double(p.DataType);
                    params(i).FixedValue  = double(p.FixedValue);

                    % DefaultValue / MinValue / MaxValue are C unions.
                    % Read as real64_T (largest member); the S-Function
                    % re-casts to the declared DataType at run time.
                    try
                        params(i).DefaultValue = double(p.DefaultValue.Real64_Val);
                        params(i).MinValue     = double(p.MinValue.Real64_Val);
                        params(i).MaxValue     = double(p.MaxValue.Real64_Val);
                    catch
                        params(i).DefaultValue = 0;
                        params(i).MinValue     = -realmax;
                        params(i).MaxValue     =  realmax;
                    end
                end
            catch ME
                warning('CIGRE:ModelInfo:ParamReadFailed', ...
                    'Failed to read parameter array: %s', ME.message);
            end
        end

        function str = readCString(ptr, maxLen)
        % Read a null-terminated C string from a lib.pointer (char*).
            if nargin < 2
                maxLen = 512;
            end
            str = "";
            if isempty(ptr)
                return
            end
            if isnumeric(ptr) && ptr == 0
                return
            end
            try
                setdatatype(ptr, 'int8Ptr', 1, maxLen);
                bytes    = uint8(ptr.Value);
                nullIdx  = find(bytes == 0, 1);
                if isempty(nullIdx)
                    str = string(char(bytes));
                else
                    str = string(char(bytes(1:nullIdx-1)));
                end
            catch
                str = "";
            end
        end

    end % private static methods

end
