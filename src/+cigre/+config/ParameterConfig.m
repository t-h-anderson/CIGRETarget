classdef ParameterConfig

    properties
        Name (1,1) string
        IsVisible (1,1) logical = true
        OverrideDefault (1,1) double = NaN % NaN indicates no override is specified
    end

    methods
        function obj = ParameterConfig(nvp)
            arguments
                nvp.Name (1,1) string
                nvp.IsVisible (1,1) logical = true
                nvp.OverrideDefault (1,1) double = NaN
            end

            obj.Name = nvp.Name;
            obj.IsVisible = nvp.IsVisible;
            obj.OverrideDefault = nvp.OverrideDefault;
        end

        function value = hasOverrideDefault(obj)
            % Determine whether an explicit default override has been provided
            value = ~isnan(obj.OverrideDefault);
        end
    end
end
