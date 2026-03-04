classdef tTranslateTypes < matlab.unittest.TestCase
    % Unit tests for util.TranslateTypes.
    %
    % TranslateTypes encodes the full mapping between Simulink C types and
    % CIGRE C types, and provides translateType to convert between them.
    %
    % Test strategy:
    %   - Validate internal consistency of the type table constants
    %   - Test each supported type maps to the correct CIGRE output
    %   - Test multi-word typedef detection (error path)
    %   - Test unknown type warning behaviour
    %   - Test output shape matches input shape
    %
    % Note: translateType requires a Simulink model to read DataTypeReplacement
    % on MATLAB >= R2023a. Tests that exercise translateType directly are
    % therefore tagged "RequiresSimulink" and skipped here. The constant
    % arrays and structural consistency checks have no such dependency.

    methods (Test)

        % --- Type table internal consistency -------------------------------

        function allTypeMappingArraysAreSameLength(testCase)
            % The four type arrays must be the same length so that the
            % column-wise mapping is unambiguous. A length mismatch means
            % at least one type is silently unmapped.
            nStandard = numel(util.TranslateTypes.StandardTypes);
            nSimulink = numel(util.TranslateTypes.SimulinkTypes);
            nCigre    = numel(util.TranslateTypes.CigreTypes);
            nAltSL    = numel(util.TranslateTypes.AltSLTypes);

            testCase.verifyEqual(nSimulink, nStandard, ...
                "SimulinkTypes length does not match StandardTypes");
            testCase.verifyEqual(nCigre, nStandard, ...
                "CigreTypes length does not match StandardTypes");
            testCase.verifyEqual(nAltSL, nStandard, ...
                "AltSLTypes length does not match StandardTypes");
        end

        function standardTypesAreUniqueStrings(testCase)
            % Duplicate entries in StandardTypes would cause the reverse
            % lookup to return an ambiguous result.
            types = util.TranslateTypes.StandardTypes;
            testCase.verifyEqual(numel(unique(types)), numel(types), ...
                "StandardTypes contains duplicate entries");
        end

        function typeArraysContainNoEmptyEntries(testCase)
            % An empty string in any type array would silently match the
            % wrong type during translation.
            testCase.verifyTrue(all(strlength(util.TranslateTypes.StandardTypes) > 0));
            testCase.verifyTrue(all(strlength(util.TranslateTypes.SimulinkTypes) > 0));
            testCase.verifyTrue(all(strlength(util.TranslateTypes.CigreTypes) > 0));
            testCase.verifyTrue(all(strlength(util.TranslateTypes.AltSLTypes) > 0));
        end

        % --- Known type mappings (spot checks) -----------------------------

        function doubleIsMappedToSimulinkRealT(testCase)
            % "double" must map to "real_T" in the Simulink type set —
            % this is the most common signal type in models.
            idx = util.TranslateTypes.StandardTypes == "double";
            testCase.verifyEqual(util.TranslateTypes.SimulinkTypes(idx), "real_T");
        end

        function doubleIsMappedToCigreReal64T(testCase)
            % "double" must map to "real64_T" in the CIGRE type set.
            idx = util.TranslateTypes.StandardTypes == "double";
            testCase.verifyEqual(util.TranslateTypes.CigreTypes(idx), "real64_T");
        end

        function singleIsMappedToSimulinkReal32T(testCase)
            idx = util.TranslateTypes.StandardTypes == "single";
            testCase.verifyEqual(util.TranslateTypes.SimulinkTypes(idx), "real32_T");
        end

        function singleIsMappedToCigreReal32T(testCase)
            idx = util.TranslateTypes.StandardTypes == "single";
            testCase.verifyEqual(util.TranslateTypes.CigreTypes(idx), "real32_T");
        end

        function int32IsMappedToSimulinkInt32T(testCase)
            idx = util.TranslateTypes.StandardTypes == "int32";
            testCase.verifyEqual(util.TranslateTypes.SimulinkTypes(idx), "int32_T");
        end

        function booleanIsMappedToCigreUint8T(testCase)
            % CIGRE does not have a native boolean type, so boolean must
            % map to uint8_T rather than boolean_T.
            idx = util.TranslateTypes.StandardTypes == "boolean";
            testCase.verifyEqual(util.TranslateTypes.CigreTypes(idx), "uint8_T");
        end

        function booleanIsMappedToSimulinkBooleanT(testCase)
            idx = util.TranslateTypes.StandardTypes == "boolean";
            testCase.verifyEqual(util.TranslateTypes.SimulinkTypes(idx), "boolean_T");
        end

        function uint8IsMappedToSimulinkUint8T(testCase)
            idx = util.TranslateTypes.StandardTypes == "uint8";
            testCase.verifyEqual(util.TranslateTypes.SimulinkTypes(idx), "uint8_T");
        end

        function uint8IsMappedToCigreUint8T(testCase)
            idx = util.TranslateTypes.StandardTypes == "uint8";
            testCase.verifyEqual(util.TranslateTypes.CigreTypes(idx), "uint8_T");
        end

        % --- Symmetry / structural checks ----------------------------------

        function simulinkAndCigreHaveDistinctIntegerMappings(testCase)
            % Ensure the double entry differs between Simulink and CIGRE —
            % "double" maps to "real_T" in Simulink but "real64_T" in CIGRE.
            % This catches any accidental copy-paste between columns.
            doubleIdx = util.TranslateTypes.StandardTypes == "double";
            slType    = util.TranslateTypes.SimulinkTypes(doubleIdx);
            cigreType = util.TranslateTypes.CigreTypes(doubleIdx);
            testCase.verifyNotEqual(slType, cigreType);
        end

        function signedAndUnsignedIntegersAreDistinct(testCase)
            % int32 and uint32 must map to different Simulink types so
            % that the DLL interface preserves sign information.
            int32Idx  = util.TranslateTypes.StandardTypes == "int32";
            uint32Idx = util.TranslateTypes.StandardTypes == "uint32";
            testCase.verifyNotEqual( ...
                util.TranslateTypes.SimulinkTypes(int32Idx), ...
                util.TranslateTypes.SimulinkTypes(uint32Idx));
        end

        % --- Multi-word typedef error path ---------------------------------

        function multiWordTypedefThrowsError(testCase)
            % Types like "int64m_T" are produced when Simulink falls back
            % to a multi-word representation and are not supported. The
            % function must error rather than silently produce wrong output.
            testCase.verifyError( ...
                @() util.TranslateTypes.translateType("int64m_T", ...
                    "From", "Simulink", "To", "CIGRE"), ...
                ?MException);
        end

        function errorMessageNamesTheProblematicType(testCase)
            % The error message must include the offending type so the user
            % can trace which signal caused the failure.
            try
                util.TranslateTypes.translateType("int64m_T", ...
                    "From", "Simulink", "To", "CIGRE");
                testCase.verifyFail("Expected an error but none was thrown");
            catch me
                testCase.verifyTrue(contains(me.message, "int64m_T"), ...
                    "Error message should name the problematic type");
            end
        end

        function multipleTypesOnlyNeedsOneMultiWordToError(testCase)
            % Even when translating a batch of types, one multi-word type
            % anywhere in the array must cause an error.
            testCase.verifyError( ...
                @() util.TranslateTypes.translateType(["real_T", "int64m_T"], ...
                    "From", "Simulink", "To", "CIGRE"), ...
                ?MException);
        end

        % --- Unknown type warning path -------------------------------------

        function unknownTypeIssuesError(testCase)
            % An unrecognised type should produce an error
            testCase.verifyError( ...
                @() util.TranslateTypes.translateType("not_a_real_type_T", ...
                    "From", "Simulink", "To", "CIGRE"), ...
                "CIGRE:TranslateTypes:UnknownType");
        end

        % --- Output shape --------------------------------------------------

        function scalarInputProducesScalarOutput(testCase)
            % translateType must return a 1x1 string for a single type input.
            result = testCase.verifyWarningFree( ...
                @() util.TranslateTypes.translateType("real_T", ...
                    "From", "Simulink", "To", "CIGRE"));
            testCase.verifySize(result, [1, 1]);
        end

        function rowVectorInputProducesRowVectorOutput(testCase)
            % The output shape must match the input shape so that
            % positional alignment with other signal property arrays is
            % preserved in CIGREWriter.
            types = ["real_T", "int32_T", "uint8_T"];
            result = testCase.verifyWarningFree( ...
                @() util.TranslateTypes.translateType(types, ...
                    "From", "Simulink", "To", "CIGRE"));
            testCase.verifySize(result, [1, 3]);
        end

    end

end