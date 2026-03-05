classdef ModelInfo
% MODELINFO  Parsed metadata read from a CIGRE-compliant DLL.
%
% Use the static factory method fromDLL to read model information directly
% from a DLL file:
%
%   info = cigre.importer.ModelInfo.fromDLL('MyController.dll')
%
% Properties
% ----------
%   Name, Version, Description  – strings from the Model_GetInfo struct
%   SampleTime   (double)  – FixedStepBaseSampleTime in seconds
%   EMT_RMS_Mode (uint8)   – 1=EMT, 2=RMS, 3=both
%   Inputs       (1xN struct) – Name, Description, Unit, DataType, Width
%   Outputs      (1xM struct) – same fields as Inputs
%   Parameters   (1xP struct) – Name, GroupName, Description, Unit,
%                               DataType, FixedValue,
%                               DefaultValue, MinValue, MaxValue
%
% DataType integers map to CIGRE enum IEEE_Cigre_DLLInterface_DataType:
%   1=char_T  2=int8_T  3=uint8_T  4=int16_T  5=uint16_T
%   6=int32_T 7=uint32_T  8=real32_T  9=real64_T  10=c_string_T

    properties
        Name        (1,1) string = ""
        Version     (1,1) string = ""
        Description (1,1) string = ""
        SampleTime  (1,1) double = 0
        EMT_RMS_Mode (1,1) uint8 = 1
        % Signal struct arrays (fields: Name, Description, Unit, DataType, Width)
        Inputs      (1,:) struct
        Outputs     (1,:) struct
        % Parameter struct array (fields: Name, GroupName, Description, Unit,
        %   DataType, FixedValue, DefaultValue, MinValue, MaxValue)
        Parameters  (1,:) struct
    end

    % ------------------------------------------------------------------ %
    methods (Static)

        function info = fromDLL(dllPath)
        % FROMDLL  Read ModelInfo from a CIGRE DLL file.
        %
        %   info = cigre.importer.ModelInfo.fromDLL(dllPath)
        %
        %   dllPath – absolute path to the CIGRE DLL (.dll).
        %
        % Internally calls the compiled MEX helper cigre_read_model_info
        % which loads the DLL via Windows LoadLibrary, invokes
        % Model_GetInfo(), and immediately frees the library.  This avoids
        % the MATLAB loadlibrary limitation where pointer-to-struct members
        % inside returned structs are auto-dereferenced to only the first
        % array element.
        %
        % The MEX helper is compiled automatically on first use.

            dllPath = string(dllPath);

            cigre.importer.ModelInfo.ensureMexCompiled();

            raw = cigre.importer.cigre_read_model_info(char(dllPath));

            info = cigre.importer.ModelInfo();
            info.Name        = string(raw.Name);
            info.Version     = string(raw.Version);
            info.Description = string(raw.Description);
            info.SampleTime  = double(raw.SampleTime);
            info.EMT_RMS_Mode = uint8(raw.EMT_RMS_Mode);
            info.Inputs      = raw.Inputs;
            info.Outputs     = raw.Outputs;
            info.Parameters  = raw.Parameters;
        end

        function slType = cigreTypeToSimulink(cigreDataType)
        % CIGRETYPETOSIMULNK  Map a CIGRE DataType integer to a MATLAB/Simulink
        % type name string.
        %
        %   slType = cigre.importer.ModelInfo.cigreTypeToSimulink(cigreDataType)
        %
        % Mapping (from IEEE_Cigre_DLLInterface_types.h):
        %   1  char_T     -> 'int8'
        %   2  int8_T     -> 'int8'
        %   3  uint8_T    -> 'uint8'
        %   4  int16_T    -> 'int16'
        %   5  uint16_T   -> 'uint16'
        %   6  int32_T    -> 'int32'
        %   7  uint32_T   -> 'uint32'
        %   8  real32_T   -> 'single'
        %   9  real64_T   -> 'double'
        %   10 c_string_T -> 'int8'  (treat as char array)

            persistent typeTable
            if isempty(typeTable)
                typeTable = [ ...
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
            keys = double(typeTable(:, 1));
            idx  = find(keys == double(cigreDataType), 1);
            if isempty(idx)
                error('CIGRE:ModelInfo:UnknownType', ...
                    'Unknown CIGRE DataType enum value: %d', cigreDataType);
            end
            slType = typeTable(idx, 2);
        end

    end % public static methods

    % ------------------------------------------------------------------ %
    methods (Static, Access = private)

        function ensureMexCompiled()
        % Compile the cigre_read_model_info MEX function if not already built.
            mexName  = 'cigre_read_model_info';
            importer = fullfile(cigreRoot(), 'src', '+cigre', '+importer');
            src      = fullfile(importer, [mexName '.c']);
            incl     = fullfile(cigreRoot(), 'src', 'CIGRESource');

            % Check whether the MEX binary is already on the path / in the
            % importer folder.
            if exist(mexName, 'file') == 3
                return   % Already compiled and on path
            end

            if ~isfile(src)
                error('CIGRE:ModelInfo:MexSourceMissing', ...
                    'MEX source not found: %s', src);
            end

            fprintf('Compiling %s.c (first use)...\n', mexName);
            try
                mex('-outdir', importer, src, ['-I' incl]);
                fprintf('Done.\n');
            catch ME
                error('CIGRE:ModelInfo:MexCompileFailed', ...
                    'Failed to compile %s:\n%s\n\n' + ...
                    'Run "mex -setup C" to configure a compiler.', ...
                    src, ME.message);
            end
        end

    end % private static methods

end
