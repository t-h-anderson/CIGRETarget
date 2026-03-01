classdef ParameterConfiguration

    properties
        Parameters (1,:) cigre.config.ParameterConfig = cigre.config.ParameterConfig.empty(1,0)
    end

    methods (Static)

        function obj = fromFile(filePath)
            arguments
                filePath (1,1) string {mustBeFile}
            end

            raw = readtable(filePath, "TextType", "string");

            % Validate expected columns are present
            requiredColumns = ["Name", "IsVisible"];
            missingColumns = requiredColumns(~ismember(requiredColumns, string(raw.Properties.VariableNames)));
            if ~isempty(missingColumns)
                error("CIGRE:ParameterConfiguration:MissingColumns", ...
                    "Parameter config file is missing required columns: %s", strjoin(missingColumns, ", "));
            end

            hasOverrideColumn = ismember("OverrideDefault", string(raw.Properties.VariableNames));

            configs = cigre.config.ParameterConfig.empty(1, 0);
            for i = 1:height(raw)
                nvpArgs = {"Name", raw.Name(i), "IsVisible", logical(raw.IsVisible(i))};

                if hasOverrideColumn && ~ismissing(raw.OverrideDefault(i))
                    nvpArgs = [nvpArgs, {"OverrideDefault", raw.OverrideDefault(i)}]; %#ok<AGROW>
                end

                configs(end+1) = cigre.config.ParameterConfig(nvpArgs{:}); %#ok<AGROW>
            end

            obj = cigre.config.ParameterConfiguration("Parameters", configs);
        end

        function obj = fromParameters(parameters)
            % Construct directly from a ParameterConfig array, useful for testing
            arguments
                parameters (1,:) cigre.config.ParameterConfig
            end

            obj = cigre.config.ParameterConfiguration("Parameters", parameters);
        end

    end

    methods

        function obj = ParameterConfiguration(nvp)
            arguments
                nvp.Parameters (1,:) cigre.config.ParameterConfig = cigre.config.ParameterConfig.empty(1,0)
            end

            obj.Parameters = nvp.Parameters;
        end

        function visible = isVisible(obj, externalName)
            % Parameters absent from the config are treated as visible by default,
            % so the config acts as a selective opt-out rather than an allowlist
            arguments
                obj (1,1)
                externalName (1,1) string
            end

            idx = obj.findIndex(externalName);
            if isempty(idx)
                visible = true;
            else
                visible = obj.Parameters(idx).IsVisible;
            end
        end

        function value = effectiveDefault(obj, externalName, modelDefault)
            % Return the override default if configured, otherwise fall back
            % to the model default so hidden parameters always have a concrete value
            arguments
                obj (1,1)
                externalName (1,1) string
                modelDefault (1,1) double
            end

            idx = obj.findIndex(externalName);
            if ~isempty(idx) && obj.Parameters(idx).hasOverrideDefault()
                value = obj.Parameters(idx).OverrideDefault;
            else
                value = modelDefault;
            end
        end

        function [visibleParams, hiddenParams] = partitionParameters(obj, allParams)
            % Split a Variable array into visible and hidden sets, applying
            % default overrides so each parameter carries its effective default value
            arguments
                obj (1,1)
                allParams (1,:) cigre.description.Variable
            end

            isVisibleMask = arrayfun(@(p) obj.isVisible(p.SimulinkName), allParams);

            visibleParams = allParams(isVisibleMask);
            hiddenParams  = allParams(~isVisibleMask);

            % Apply effective defaults so the writer doesn't need to call back
            % into the config for each parameter individually
            for i = 1:numel(visibleParams)
                visibleParams(i).DefaultValue = obj.effectiveDefault(...
                    visibleParams(i).ExternalName, visibleParams(i).DefaultValue);
            end

            for i = 1:numel(hiddenParams)
                hiddenParams(i).DefaultValue = obj.effectiveDefault(...
                    hiddenParams(i).ExternalName, hiddenParams(i).DefaultValue);
            end
        end

        function [missingFromConfig, superfluousInConfig] = validateAgainstModel(obj, allParams)
            % Check the config against the model's full parameter list to surface
            % mismatches early, before they cause silent errors during code generation.
            % missingFromConfig: model parameters with no entry in the config.
            % superfluousInConfig: config entries that match no model parameter.
            arguments
                obj (1,1)
                allParams (1,:) cigre.description.Variable
            end

            modelNames  = string([allParams.ExternalName]);
            configNames = string([obj.Parameters.Name]);

            missingFromConfig    = modelNames(~ismember(modelNames, configNames));
            superfluousInConfig  = configNames(~ismember(configNames, modelNames));
        end

    end

    methods (Access = private)

        function idx = findIndex(obj, externalName)
            % Return the index of a named parameter in the config array,
            % or empty if it is not present
            arguments
                obj (1,1)
                externalName (1,1) string
            end

            idx = find(string({obj.Parameters.Name}) == externalName, 1);
        end

    end
end
