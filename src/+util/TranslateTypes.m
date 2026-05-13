classdef TranslateTypes < handle

    properties (Constant)
        StandardTypes = ["double", "single", "int32", "int16", "int8", "uint32", "uint16", "uint8", "boolean", "int", "uint", "char"]
        SimulinkTypes = ["real_T", "real32_T", "int32_T", "int16_T", "int8_T", "uint32_T", "uint16_T", "uint8_T", "boolean_T", "int32_T", "uint32_T", "char_T"]
        CigreTypes = ["real64_T", "real32_T", "int32_T", "int16_T", "int8_T", "uint32_T", "uint16_T", "uint8_T", "uint8_T", "int32_T", "uint32_T", "char_T"]
        AltSLTypes = ["double", "float", "int32_t", "int16_t", "int8_t", "uint32_t", "uint16_t", "uint8_t", "boolean_t", "int", "unsigned int", "char"]
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

            % Multi-word typedefs (suffix m_T) appear when a type is too
            % large for the target hardware. The CIGRE DLL ABI has no
            % representation for these so reject early; a model advisor
            % check should also catch this upstream.
            idx = contains(typeIn, "m_T");
            if any(idx)
                error("Cigre dll doesn't support multi-word typedefs yet, e.g. " + typeIn(find(idx, 1)));
            end

            model = nvp.Model;
            try
                co = util.loadSystem(model); %#ok<NASGU>
            catch
                model = string(nan);
            end


            if verLessThan("MATLAB", "9.14") 
                
                cigreMap = containers.Map(util.TranslateTypes.StandardTypes, util.TranslateTypes.CigreTypes);
                simulinkMap = containers.Map(util.TranslateTypes.StandardTypes, util.TranslateTypes.SimulinkTypes);

            elseif ismissing(nvp.Model)

                cigreMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.CigreTypes);
                simulinkMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.SimulinkTypes);

            else

                cigreMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.CigreTypes);

                model = nvp.Model;
                co = util.loadSystem(model); %#ok<NASGU>

                type = string(get_param(model, "DataTypeReplacement"));
                switch type
                    case "CDataTypesFixedWidth"
                        simulinkMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.AltSLTypes);
                    case "CoderTypedefs"
                        simulinkMap = dictionary(util.TranslateTypes.StandardTypes, util.TranslateTypes.SimulinkTypes);
                    otherwise
                        error("CIGRE:TranslateTypes:UnknownDataTypeReplacement", "Type " + type + " not supported yet");
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

            values = from.values;
            values = reshape(values, [], 1);
            % Each column of idx flags where typeIn(i) appears in the "from" mapping.
            idx = (string(values) == typeIn);

            missingTypes = typeIn(~any(idx, 1));
            if ~isempty(missingTypes)
                error("CIGRE:TranslateTypes:UnknownType", "Type(s) '" + strjoin(missingTypes, ", ") + "' not found in supported " + nvp.From + " type list. If this is enum, check the port data type is not set to auto. This is not supported." );
            end

            firstIdxs = zeros(nTypesIn, 1);
            for i = 1:nTypesIn
                % Take the first hit when a Simulink type maps to multiple
                % keys (e.g. boolean/uint8 collisions on the CIGRE side).
                foundIdx = find(idx(:,i), 1);
                firstIdxs(i) = foundIdx;
            end

            standardTypeKeys = from.keys;
            standardTypes = string(standardTypeKeys(firstIdxs));
            % arrayfun rather than indexing to remain compatible with the
            % containers.Map fallback used on MATLAB < R2022b.
            typeOut = arrayfun(@(x) string(to(x)), standardTypes);

            typeOut = reshape(typeOut, [], size(typeIn, 2));

        end
    end
end
