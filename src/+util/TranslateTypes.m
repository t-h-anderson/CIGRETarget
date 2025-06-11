classdef TranslateTypes < handle

    properties (Constant)
        StandardTypes = ["double",   "single",   "int32",   "int16",   "int8",   "uint32",   "uint16",   "uint8",   "boolean",   "int",     "uint",     "char"]
        SimulinkTypes = ["real_T",   "real32_T", "int32_T", "int16_T", "int8_T", "uint32_T", "uint16_T", "uint8_T", "boolean_T", "int32_T", "uint32_T", "char_T"]
        CigreTypes =    ["real64_T", "real32_T", "int32_T", "int16_T", "int8_T", "uint32_T", "uint16_T", "uint8_T", "uint8_T",   "int32_T", "uint32_T", "char_T"]
        AltSLTypes =    ["double",   "float",    "int32_t", "int16_t", "int8_t", "uint32_t", "uint16_t", "uint8_t", "boolean_t", "int",     "unsigned int", "char"]
    end

    methods (Static)
        function typeOut = translateType(typeIn, nvp)

            arguments
                typeIn (1,:) string
                nvp.From (1,1) string {mustBeMember(nvp.From, ["Simulink", "CIGRE"])}
                nvp.To (1,1) string {mustBeMember(nvp.To, ["Simulink", "CIGRE"])}
                nvp.Model (1,1) string {mustBeNonempty} = string(missing)
            end

            nTypesIn = numel(typeIn);

            % If type is too large for target hardware type gets renamed e.g. int64m_T
            % This should be caught by a model advisor check
            idx = contains(typeIn, "m_T");
            if any(idx)
                error("Cigre dll doesn't support multi-word typedefs yet, e.g. " + typeIn(find(idx, 1)));
            end

            model = nvp.Model;
            co = util.loadSystem(model); %#ok<NASGU>


            if verLessThan("MATLAB", "9.14")

                cigreMap = containers.Map(util.TranslateTypes.StandardTypes, util.TranslateTypes.CigreTypes);
                simulinkMap = containers.Map(util.TranslateTypes.StandardTypes, util.TranslateTypes.SimulinkTypes);

            else

                cigreMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.CigreTypes);

                % Get correct replacement types
                type = get_param(model, "DataTypeReplacement");
                switch type
                    case 'CDataTypesFixedWidth'
                        simulinkMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.AltSLTypes);
                    case 'CoderTypedefs'
                        simulinkMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.SimulinkTypes);
                    otherwise
                        error("Type " + type + " not supported yet");
                end

            end

            % Correct for any custom replacement types
            if ~ismissing(model)
                types = get_param(model, "ReplacementTypes");
                typeNames = string(fields(types));

                for i = 1:numel(typeNames)
                    thisTypeName = typeNames(i);
                    val = types.(thisTypeName);
                    if ~isempty(val)
                        simulinkMap(thisTypeName) = val;
                    end
                end
            end

            % Order the mappings
            if nvp.From == "Simulink"
                from = simulinkMap;
            else
                from = cigreMap;
            end


            if nvp.To == "Simulink"
                to = simulinkMap;
            else
                to = cigreMap;
            end

            % Search for input types in from map values
            values = from.values;
            values = reshape(values, [], 1);
            idx = (string(values) == typeIn); % Each column indicates where the input(i) has been found

            missingTypes = typeIn(~any(idx, 1));
            if ~isempty(missingTypes)
                typeOut = typeIn;
                return
                error("Type(s) '" + strjoin(missingTypes, ", ") + "' not found in supported " + nvp.From + " type list. If this is enum, check the port data type is not set to auto. This is not supported." );
            end

            firstIdxs = zeros(nTypesIn, 1);
            for i = 1:nTypesIn
                foundIdx = find(idx(:,i), 1);  % Take the first one if multiple are found
                firstIdxs(i) = foundIdx;
            end

            % Find the corresponding "to" types based on standard type keys
            standardTypeKeys = from.keys;
            standardTypes = string(standardTypeKeys(firstIdxs));
            typeOut = arrayfun(@(x) string(to(x)), standardTypes); % Use arrayfun to support containers.map in 2020a

            typeOut = reshape(typeOut, [], size(typeIn, 2));

        end
    end
end
