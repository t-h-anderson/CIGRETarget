classdef InterfaceInstance <handle

    properties
        InputData

        IsInitialised (1,1) logical = false
        Instance
        Struct
        InMap (1,1) cigre.dll.DataMap
        OutMap (1,1) cigre.dll.DataMap
        ParamMap (1,1) cigre.dll.DataMap
        StateMemory (1,1)
    end

    methods
        function obj = InterfaceInstance(inputs, outputs, parameters, nvp)
            % The s return value is needed as data.Value comes back as
            % voidpointer type
            arguments
                inputs
                outputs
                parameters
                nvp.IntStates
                nvp.Time (1,1) double = 0 % Make non-zero if not first timestep
            end

            obj.InputData = inputs;

            if isfield(nvp, "IntStates")
                obj.IsInitialised = true;
            else
                obj.IsInitialised = false;
                nvp.IntStates (1,1) = libpointer('int32Ptr', zeros(1,100000));
            end

            intstate4model = nvp.IntStates;

            %% Input
            inMap = cigre.dll.DataMap.create(inputs);
            in = inMap.Words;

            %% Parameters
            paramMap = cigre.dll.DataMap.create({parameters.Value});
            param = paramMap.Words;

            %% Output
            outMap = cigre.dll.DataMap.create(outputs);
            out = outMap.Words;

            out = zeros(1, numel(out)); % TODO: How do we detect bit packing? Is it always 8?

            inputs = libpointer('uint8Ptr', in);
            outputs = libpointer('uint8Ptr', out);
            parameters = libpointer('uint8Ptr', param);

            %% IEEE_Cigre_DLLInterface_Instance
            % void *          ExternalInputs;         // Input signals array
            % void *          ExternalOutputs;        // Output signals array
            % void *          Parameters;             // Parameters array
            % real64_T        Time;                   // Current simulation time
            % const uint8_T   SimTool_EMT_RMS_Mode;   // Mode: EMT = 1, RMS = 2
            % const char_T *  LastErrorMessage;       // Error string pointer
            % const char_T *  LastGeneralMessage;     // General message
            % int32_T *       IntStates;              // Int State array
            % real32_T *      FloatStates;            // Float State array
            % real64_T *      DoubleStates;           // Double State array

            s = struct(...
                "ExternalInputs", inputs, ...
                "ExternalOutputs", outputs, ...
                "Parameters", parameters, ...
                "Time", nvp.Time, ... % Used in First Call flag
                "SimTool_EMT_RMS_Mode", 1, ...
                "LastErrorMessage", [], ...
                "LastGeneralMessage", [], ...
                "IntStates", intstate4model, ...
                "FloatStates", [], ...
                "DoubleStates", [] ...
                );

            data = libpointer("s_IEEE_Cigre_DLLInterface_Instance", s);

            % Map to object
            obj.InMap = inMap;
            obj.OutMap = outMap;
            obj.ParamMap = paramMap;
            obj.Instance = data;
            obj.Struct = s;
            obj.StateMemory = intstate4model;
        end

        function updateInputs(obj, input, nvp)
            arguments
                obj
                input = obj.InputData
                nvp.Row (1,1) double = 1
            end

            %% input
            inMap = cigre.dll.DataMap.create(input, "Row", nvp.Row);
            in = inMap.Words;

            % Update inputs
            inputs = libpointer('uint8Ptr', in);
            s = obj.Struct;
            s.ExternalInputs = inputs;

            data = libpointer("s_IEEE_Cigre_DLLInterface_Instance", s);

            % Map to object
            obj.InMap = inMap;
            obj.Instance = data;
            obj.Struct = s;

        end

        function val = getOutput(obj)

            out = obj.Struct.ExternalOutputs.Value;

            outMap = obj.OutMap;

            outMap.Words = out;

            outMap = outMap.wordsToData();

            obj.OutMap = outMap;

            val = outMap.Data;

        end

        function clear(obj)
            delete(obj.Instance);
        end

    end

end

