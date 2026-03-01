classdef tParameterConfiguration < matlab.unittest.TestCase

    methods (Test)

        %% ParameterConfig

        function parameterConfigDefaultsToVisible(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK");
            testCase.verifyTrue(config.IsVisible);
        end

        function parameterConfigDefaultsToNoOverride(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK");
            testCase.verifyFalse(config.hasOverrideDefault());
        end

        function parameterConfigReportsOverrideWhenSet(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "OverrideDefault", 5.0);
            testCase.verifyTrue(config.hasOverrideDefault());
        end

        function parameterConfigStoresValues(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false, "OverrideDefault", 3.5);
            testCase.verifyEqual(config.Name, "gainK");
            testCase.verifyFalse(config.IsVisible);
            testCase.verifyEqual(config.OverrideDefault, 3.5);
        end

        %% isVisible

        function isVisibleReturnsTrueForUnknownParameter(testCase)
            % Parameters absent from the config default to visible so that
            % models without a config file are unaffected
            obj = cigre.config.ParameterConfiguration();
            testCase.verifyTrue(obj.isVisible("anyParam"));
        end

        function isVisibleReturnsTrueForExplicitlyVisibleParameter(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", true);
            obj    = cigre.config.ParameterConfiguration.fromParameters(config);
            testCase.verifyTrue(obj.isVisible("gainK"));
        end

        function isVisibleReturnsFalseForHiddenParameter(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false);
            obj    = cigre.config.ParameterConfiguration.fromParameters(config);
            testCase.verifyFalse(obj.isVisible("gainK"));
        end

        %% effectiveDefault

        function effectiveDefaultReturnsModelDefaultWhenNoConfigEntry(testCase)
            obj    = cigre.config.ParameterConfiguration();
            result = obj.effectiveDefault("gainK", 2.0);
            testCase.verifyEqual(result, 2.0);
        end

        function effectiveDefaultReturnsModelDefaultWhenNoOverrideSet(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false);
            obj    = cigre.config.ParameterConfiguration.fromParameters(config);
            result = obj.effectiveDefault("gainK", 2.0);
            testCase.verifyEqual(result, 2.0);
        end

        function effectiveDefaultReturnsOverrideWhenSet(testCase)
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false, "OverrideDefault", 7.0);
            obj    = cigre.config.ParameterConfiguration.fromParameters(config);
            result = obj.effectiveDefault("gainK", 2.0);
            testCase.verifyEqual(result, 7.0);
        end

        function effectiveDefaultOverrideAppliesForVisibleParameterToo(testCase)
            % Override defaults apply regardless of visibility — visible params
            % use the override as the header default value
            config = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", true, "OverrideDefault", 9.0);
            obj    = cigre.config.ParameterConfiguration.fromParameters(config);
            result = obj.effectiveDefault("gainK", 2.0);
            testCase.verifyEqual(result, 9.0);
        end

        %% partitionParameters

        function partitionSplitsIntoVisibleAndHidden(testCase)
            configs = [
                cigre.config.ParameterConfig("Name", "p1",  "IsVisible", true)
                cigre.config.ParameterConfig("Name", "p2",  "IsVisible", false)
                cigre.config.ParameterConfig("Name", "p3",  "IsVisible", true)
            ];
            obj = cigre.config.ParameterConfiguration.fromParameters(configs);

            allParams = testCase.makeVariables(["p1", "p2", "p3"], [1.0, 2.0, 3.0]);
            [visible, hidden] = obj.partitionParameters(allParams);

            testCase.verifyEqual(string([visible.SimulinkName]), ["p1", "p3"]);
            testCase.verifyEqual(string([hidden.SimulinkName]),  ["p2"]);
        end

        function partitionTreatsUnknownParameterAsVisible(testCase)
            % Parameters not mentioned in the config should pass through unaffected
            obj       = cigre.config.ParameterConfiguration();
            allParams = testCase.makeVariables(["p1", "p2"], [1.0, 2.0]);

            [visible, hidden] = obj.partitionParameters(allParams);

            testCase.verifyEqual(numel(visible), 2);
            testCase.verifyEmpty(hidden);
        end

        function partitionAppliesOverrideDefaultToVisibleParam(testCase)
            configs = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", true, "OverrideDefault", 5.0);
            obj     = cigre.config.ParameterConfiguration.fromParameters(configs);

            allParams = testCase.makeVariables("gainK", 1.0);
            [visible, ~] = obj.partitionParameters(allParams);

            testCase.verifyEqual(visible.DefaultValue, 5.0);
        end

        function partitionAppliesModelDefaultToHiddenParamWithNoOverride(testCase)
            configs = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false);
            obj     = cigre.config.ParameterConfiguration.fromParameters(configs);

            allParams = testCase.makeVariables("gainK", 3.0);
            [~, hidden] = obj.partitionParameters(allParams);

            testCase.verifyEqual(hidden.DefaultValue, 3.0);
        end

        function partitionAppliesOverrideDefaultToHiddenParam(testCase)
            configs = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", false, "OverrideDefault", 9.0);
            obj     = cigre.config.ParameterConfiguration.fromParameters(configs);

            allParams = testCase.makeVariables("gainK", 3.0);
            [~, hidden] = obj.partitionParameters(allParams);

            testCase.verifyEqual(hidden.DefaultValue, 9.0);
        end

        function partitionDoesNotMutateOriginalVariables(testCase)
            % Variable is a value class so partitioning should not affect the
            % original array passed in
            configs   = cigre.config.ParameterConfig("Name", "gainK", "IsVisible", true, "OverrideDefault", 5.0);
            obj       = cigre.config.ParameterConfiguration.fromParameters(configs);
            allParams = testCase.makeVariables("gainK", 1.0);

            obj.partitionParameters(allParams);

            testCase.verifyEqual(allParams.DefaultValue, 1.0);
        end

        %% validateAgainstModel

        function validateReturnsEmptyWhenConfigMatchesModel(testCase)
            configs = [
                cigre.config.ParameterConfig("Name", "p1")
                cigre.config.ParameterConfig("Name", "p2")
            ];
            obj       = cigre.config.ParameterConfiguration.fromParameters(configs);
            allParams = testCase.makeVariables(["p1", "p2"], [1.0, 2.0]);

            [missing, superfluous] = obj.validateAgainstModel(allParams);

            testCase.verifyEmpty(missing);
            testCase.verifyEmpty(superfluous);
        end

        function validateReportsMissingConfigEntry(testCase)
            % p2 exists in the model but is not in the config
            configs   = cigre.config.ParameterConfig("Name", "p1");
            obj       = cigre.config.ParameterConfiguration.fromParameters(configs);
            allParams = testCase.makeVariables(["p1", "p2"], [1.0, 2.0]);

            [missing, superfluous] = obj.validateAgainstModel(allParams);

            testCase.verifyEqual(missing, "p2");
            testCase.verifyEmpty(superfluous);
        end

        function validateReportsSuperfluousConfigEntry(testCase)
            % p3 is in the config but does not exist in the model
            configs = [
                cigre.config.ParameterConfig("Name", "p1")
                cigre.config.ParameterConfig("Name", "p3")
            ];
            obj       = cigre.config.ParameterConfiguration.fromParameters(configs);
            allParams = testCase.makeVariables("p1", 1.0);

            [missing, superfluous] = obj.validateAgainstModel(allParams);

            testCase.verifyEmpty(missing);
            testCase.verifyEqual(superfluous, "p3");
        end

        function validateReportsBothMissingAndSuperfluous(testCase)
            configs   = cigre.config.ParameterConfig("Name", "p3");
            obj       = cigre.config.ParameterConfiguration.fromParameters(configs);
            allParams = testCase.makeVariables(["p1", "p2"], [1.0, 2.0]);

            [missing, superfluous] = obj.validateAgainstModel(allParams);

            testCase.verifyEqual(sort(missing),     sort(["p1", "p2"]));
            testCase.verifyEqual(superfluous, "p3");
        end

    end

    methods (Static, Access = private)

        function params = makeVariables(names, defaults)
            % Construct a minimal Variable array for testing without needing Simulink
            arguments
                names    (1,:) string
                defaults (1,:) double = ones(1, numel(names))
            end

            params = cigre.description.Variable.empty(1, 0);
            for i = 1:numel(names)
                params(end+1) = cigre.description.Variable( ...
                    "SimulinkName", names(i), ...
                    "ExternalName", names(i), ...
                    "DefaultValue", defaults(i));
            end
        end

    end

end