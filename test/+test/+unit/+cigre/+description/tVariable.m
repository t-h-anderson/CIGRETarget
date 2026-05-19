classdef tVariable < matlab.unittest.TestCase
    % Unit tests for cigre.description.Variable.
    %
    % Variable represents a single typed signal, parameter, or state
    % variable extracted from the Simulink code descriptor. Its tree
    % structure (via NestedVariable) supports parameter structs. The key
    % behaviours tested here are those that don't require a live Simulink
    % session: leaf detection, recursive leaf traversal, the create factory,
    % and the IsModelArgument dependent property.

    methods (Test)

        % --- IsLeaf --------------------------------------------------------

        function variableWithNoChildrenIsLeaf(testCase)
            v = cigre.description.Variable("SimulinkName", "mySignal");
            testCase.verifyTrue(v.IsLeaf);
        end

        function variableWithChildrenIsNotLeaf(testCase)
            child = cigre.description.Variable("SimulinkName", "child");
            parent = cigre.description.Variable( ...
                "SimulinkName", "parent", ...
                "NestedVariable", child);
            testCase.verifyFalse(parent.IsLeaf);
        end

        % --- getLeaves -----------------------------------------------------

        function getSingleLeafFromFlatVariable(testCase)
            v = cigre.description.Variable("SimulinkName", "x");
            leaves = v.getLeaves();
            testCase.verifyNumElements(leaves, 1);
            testCase.verifyEqual(leaves.SimulinkName, "x");
        end

        function getLeavesFromSingleLevelNesting(testCase)
            % A parent with two leaf children should return those two
            % children, not the parent itself.
            child1 = cigre.description.Variable("SimulinkName", "a");
            child2 = cigre.description.Variable("SimulinkName", "b");
            parent = cigre.description.Variable( ...
                "SimulinkName", "parent", ...
                "NestedVariable", [child1, child2]);
            leaves = parent.getLeaves();
            testCase.verifyNumElements(leaves, 2);
            testCase.verifyEqual(string([leaves.SimulinkName]), ["a", "b"]);
        end

        function getLeavesFromTwoLevelNesting(testCase)
            % Leaf extraction must be fully recursive: leaves at any depth
            % should be returned, and intermediate nodes should not.
            grandchild1 = cigre.description.Variable("SimulinkName", "gc1");
            grandchild2 = cigre.description.Variable("SimulinkName", "gc2");
            child = cigre.description.Variable( ...
                "SimulinkName", "child", ...
                "NestedVariable", [grandchild1, grandchild2]);
            root = cigre.description.Variable( ...
                "SimulinkName", "root", ...
                "NestedVariable", child);
            leaves = root.getLeaves();
            testCase.verifyNumElements(leaves, 2);
            leafNames = string([leaves.SimulinkName]);
            testCase.verifyTrue(ismember("gc1", leafNames));
            testCase.verifyTrue(ismember("gc2", leafNames));
        end

        function getLeavesFromMixedTree(testCase)
            % A tree where some branches are leaves and others are not should
            % return only the actual leaves regardless of depth.
            deepLeaf = cigre.description.Variable("SimulinkName", "deep");
            middleNode = cigre.description.Variable( ...
                "SimulinkName", "middle", ...
                "NestedVariable", deepLeaf);
            shallowLeaf = cigre.description.Variable("SimulinkName", "shallow");
            root = cigre.description.Variable( ...
                "SimulinkName", "root", ...
                "NestedVariable", [middleNode, shallowLeaf]);
            leaves = root.getLeaves();
            testCase.verifyNumElements(leaves, 2);
            leafNames = string([leaves.SimulinkName]);
            testCase.verifyTrue(ismember("deep", leafNames));
            testCase.verifyTrue(ismember("shallow", leafNames));
        end

        function getLeavesOnArrayOfVariables(testCase)
            % getLeaves must work when called on an array of Variables —
            % the system uses this when iterating CIGREParameters.
            a = cigre.description.Variable("SimulinkName", "a");
            b = cigre.description.Variable("SimulinkName", "b");
            vars = [a,b];
            leaves = vars.getLeaves();
            testCase.verifyNumElements(leaves, 2);
        end

        % --- CIGREName defaults --------------------------------------------

        function cigreNameDefaultsToSimulinkName(testCase)
            % When CIGREName is not set, it should be derived from
            % SimulinkName via makeValidName so the C identifier is valid.
            v = cigre.description.Variable("SimulinkName", "myParam");
            testCase.verifyEqual(v.CIGREName, "myParam");
        end

        function cigreNameMakesIdentifierValid(testCase)
            % SimulinkName may contain characters invalid in C identifiers;
            % CIGREName must sanitise these.
            simulinkName = "my param";
            v = cigre.description.Variable("SimulinkName", simulinkName);

            expected = matlab.lang.makeValidName(simulinkName);
            testCase.verifyEqual(v.CIGREName, expected);
        end

        function explicitCIGRENameIsPreserved(testCase)
            v = cigre.description.Variable( ...
                "SimulinkName", "myParam", ...
                "CIGREName", "customName");
            testCase.verifyEqual(v.CIGREName, "customName");
        end

        % --- IsModelArgument -----------------------------------------------

        function isModelArgumentFalseByDefault(testCase)
            v = cigre.description.Variable("SimulinkName", "p");
            testCase.verifyFalse(v.IsModelArgument);
        end

        function isModelArgumentTrueWhenStorageSpecifierSet(testCase)
            v = cigre.description.Variable( ...
                "SimulinkName", "p", ...
                "StorageSpecifier", "ModelArgument:myBlock");
            testCase.verifyTrue(v.IsModelArgument);
        end

        % --- create static factory -----------------------------------------

        function createScalarProducesOneObject(testCase)
            vars = cigre.description.Variable.create( ...
                "SimulinkName", "x", ...
                "Type", "real32_T");
            testCase.verifyNumElements(vars, 1);
            testCase.verifyEqual(vars.SimulinkName, "x");
            testCase.verifyEqual(vars.Type, "real32_T");
        end

        function createVectorProducesMultipleObjects(testCase)
            % Passing arrays to create should produce one Variable per entry.
            vars = cigre.description.Variable.create( ...
                "SimulinkName", ["x"; "y"; "z"], ...
                "Type", ["real32_T"; "int32_T"; "uint8_T"]);
            testCase.verifyNumElements(vars, 3);
            testCase.verifyEqual(string([vars.SimulinkName]), ["x", "y", "z"]);
        end

        % --- extract Min/Max limit defaults --------------------------------

        function extractMissingMinDefaultsToLargeNegative(testCase)
            % A floating-point parameter with no minimum must default to a
            % large *negative* bound. realmin (the smallest positive
            % double) would wrongly reject every negative value the
            % parameter can legitimately take.
            fake = test.util.FakeRangedInterface;
            fake.Type  = struct("Name", "double");
            fake.Range = struct("Min", '', "Max", '');

            minVal = cigre.description.Variable.extract(fake, "Min");

            testCase.verifyLessThan(minVal, 0, ...
                "A missing minimum must resolve to a negative lower bound");
            testCase.verifyEqual(minVal, -realmax / 2);
        end

        function extractNegInfMinDefaultsToLargeNegative(testCase)
            % An explicit -inf minimum must resolve to the same finite
            % negative bound as a missing minimum.
            fake = test.util.FakeRangedInterface;
            fake.Type  = struct("Name", "double");
            fake.Range = struct("Min", "-inf", "Max", "inf");

            minVal = cigre.description.Variable.extract(fake, "Min");

            testCase.verifyEqual(minVal, -realmax / 2);
        end

        function extractMissingMaxDefaultsToLargePositive(testCase)
            % Guards the companion Max branch so the Min default cannot be
            % "fixed" by accidentally breaking the Min/Max symmetry.
            fake = test.util.FakeRangedInterface;
            fake.Type  = struct("Name", "double");
            fake.Range = struct("Min", '', "Max", '');

            maxVal = cigre.description.Variable.extract(fake, "Max");

            testCase.verifyGreaterThan(maxVal, 0);
            testCase.verifyEqual(maxVal, realmax / 2);
        end

    end

end