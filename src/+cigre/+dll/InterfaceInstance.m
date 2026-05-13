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

    properties (Constant)
        % Pre-allocated int32 state buffer. The CIGRE ABI requires a
        % contiguous block but does not report its required size; 100k
        % words has been sufficient for every test model we ship.
        IntStateBufferSize = 100000;
    end

    methods
        function obj = InterfaceInstance(inputs, outputs, parameters, nvp)
            arguments
                inputs
                outputs
                parameters
                nvp.IntStates = []
                % Time is non-zero when restarting from a snapshot, which
                % suppresses the first-call branch inside the DLL.
                nvp.Time (1,1) double = 0
            end

            obj.InputData = inputs;

            isSnapshot = ~isempty(nvp.IntStates);
            obj.IsInitialised = isSnapshot;
            if ~isSnapshot
                nvp.IntStates = libpointer("int32Ptr", zeros(1, cigre.dll.InterfaceInstance.IntStateBufferSize));
            end

            intStateData = nvp.IntStates;

            inMap = cigre.dll.DataMap.create(inputs);
            in = inMap.Words;

            paramMap = cigre.dll.DataMap.create({parameters.Value});
            param = paramMap.Words;

            outMap = cigre.dll.DataMap.create(outputs);
            out = outMap.Words;

            % TODO: detect actual bit packing rather than assuming 8.
            out = zeros(1, numel(out));

            inputs = libpointer("uint8Ptr", in);
            outputs = libpointer("uint8Ptr", out);
            parameters = libpointer("uint8Ptr", param);

            % IEEE_Cigre_DLLInterface_Instance layout (from the spec):
            %   ExternalInputs, ExternalOutputs, Parameters,
            %   Time, SimTool_EMT_RMS_Mode (1=EMT, 2=RMS),
            %   LastErrorMessage, LastGeneralMessage,
            %   IntStates, FloatStates, DoubleStates.
            s = struct(...
                "ExternalInputs", inputs, ...
                "ExternalOutputs", outputs, ...
                "Parameters", parameters, ...
                "Time", nvp.Time, ...
                "SimTool_EMT_RMS_Mode", 1, ...
                "LastErrorMessage", [], ...
                "LastGeneralMessage", [], ...
                "IntStates", intStateData, ...
                "FloatStates", [], ...
                "DoubleStates", [] ...
                );

            data = libpointer("s_IEEE_Cigre_DLLInterface_Instance", s);

            obj.InMap = inMap;
            obj.OutMap = outMap;
            obj.ParamMap = paramMap;
            obj.Instance = data;
            obj.Struct = s;
            obj.StateMemory = intStateData;
        end

        function updateInputs(obj, input, nvp)
            arguments
                obj
                input = obj.InputData
                nvp.Row (1,1) double = 1
            end

            inMap = cigre.dll.DataMap.create(input, "Row", nvp.Row);
            in = inMap.Words;

            inputs = libpointer("uint8Ptr", in);
            s = obj.Struct;
            s.ExternalInputs = inputs;

            data = libpointer("s_IEEE_Cigre_DLLInterface_Instance", s);

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

