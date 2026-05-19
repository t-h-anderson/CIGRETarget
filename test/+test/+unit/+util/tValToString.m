classdef tValToString < matlab.unittest.TestCase
    % Unit tests for util.valToString.
    %
    % valToString converts a MATLAB value to a string representation that
    % can be eval'd back to reproduce the original value. It is used when
    % writing parameter values into the Simulink wrapper model's workspace.
    %
    % Covered cases:
    %   - Scalar double (default type - no cast prefix)
    %   - Scalar non-double (int32, single, uint8 - requires cast prefix)
    %   - String and char inputs
    %   - Row vector
    %   - Column vector
    %   - 2-D matrix (verifies row/column separator logic)
    %   - Struct with scalar and vector fields
    %   - Nested struct

    methods (Test)

        % --- Scalar numerics -----------------------------------------------

        function scalarDoubleHasNoCastPrefix(testCase)
            % Doubles are the default MATLAB type, so no cast prefix is
            % needed — the result should just be the number as a string.
            result = util.valToString(3.14);
            testCase.verifyEqual(result, "3.14");
        end

        function scalarIntegerHasCastPrefix(testCase)
            % Non-double scalars must include an explicit type cast so that
            % eval'ing the string reproduces the correct type.
            result = util.valToString(int32(7));
            testCase.verifyEqual(result, "int32(7)");
        end

        function scalarSingleHasCastPrefix(testCase)
            result = util.valToString(single(1.5));
            testCase.verifyEqual(result, "single(1.5)");
        end

        function scalarUint8HasCastPrefix(testCase)
            result = util.valToString(uint8(255));
            testCase.verifyEqual(result, "uint8(255)");
        end

        function scalarZeroDouble(testCase)
            result = util.valToString(0);
            testCase.verifyEqual(result, "0");
        end

        % --- String / char -------------------------------------------------

        function stringValueIsQuoted(testCase)
            % Strings are wrapped in double quotes so eval reproduces a string.
            result = util.valToString("hello");
            testCase.verifyEqual(result, """hello""");
        end

        % --- Vectors -------------------------------------------------------

        function rowVectorIsBracketedWithCommas(testCase)
            % Row vectors should be represented as [a, b, c].
            result = util.valToString([1.0, 2.0, 3.0]);
            testCase.verifyEqual(result, "[1, 2, 3]");
        end

        function columnVectorUseSemicolonSeparator(testCase)
            % Column vectors should use semicolons as row separators,
            % matching MATLAB's matrix literal syntax.
            result = util.valToString([1.0; 2.0; 3.0]);
            testCase.verifyEqual(result, "[1; 2; 3]");
        end

        % --- 2-D matrix ----------------------------------------------------

        function matrixRowsAreSeparatedBySemicolons(testCase)
            % This verifies the row/column separator logic that had an
            % off-by-one bug where size(s,2) was used instead of size(s,1).
            % A 2x2 matrix should produce "[1, 2; 3, 4]".
            result = util.valToString([1.0, 2.0; 3.0, 4.0]);
            testCase.verifyEqual(result, "[1, 2; 3, 4]");
        end

        function matrixLastRowHasNoTrailingSemicolon(testCase)
            % The final row must not end with a semicolon.
            result = util.valToString([1.0, 2.0; 3.0, 4.0]);
            testCase.verifyFalse(endsWith(result, ";]"));
        end

        function singleElementMatrixMatchesScalar(testCase)
            % A 1x1 array and a scalar should produce the same output.
            scalar = util.valToString(5.0);
            matrix = util.valToString(reshape(5.0, 1, 1));
            testCase.verifyEqual(scalar, matrix);
        end

        % --- Structs -------------------------------------------------------

        function structWithOneScalarField(testCase)
            % A struct is serialised as struct("fieldName", value).
            s.x = 1.0;
            result = util.valToString(s);
            testCase.verifyEqual(result, "struct(""x"", 1)");
        end

        function structWithMultipleFields(testCase)
            % All fields must appear with comma separation.
            s.a = 1.0;
            s.b = int32(2);
            result = util.valToString(s);
            testCase.verifyEqual(result, "struct(""a"", 1, ""b"", int32(2))");
        end

        function structWithVectorField(testCase)
            s.vals = [1.0, 2.0, 3.0];
            result = util.valToString(s);
            testCase.verifyEqual(result, "struct(""vals"", [1, 2, 3])");
        end

        % --- Roundtrip (eval) ----------------------------------------------

        function scalarDoubleRoundtrips(testCase)
            original = 42.5;
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        function int32ScalarRoundtrips(testCase)
            original = int32(-7);
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        function rowVectorRoundtrips(testCase)
            original = [1.0, 2.0, 3.0];
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        function matrixRoundtrips(testCase)
            original = [1.0, 2.0; 3.0, 4.0];
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        function structRoundtrips(testCase)
            original.x = 1.0;
            original.y = int32(3);
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        % --- High-precision values (no truncation) -------------------------

        function highPrecisionDoubleRoundtrips(testCase)
            % string() / num2str() truncate to ~5 significant figures;
            % valToString must preserve enough digits to reconstruct the
            % exact original value.
            original = pi;
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

        function highPrecisionDoubleNotTruncated(testCase)
            result = util.valToString(pi);
            testCase.verifyEqual(str2double(result), pi);
        end

        function highPrecisionSingleRoundtrips(testCase)
            original = single(pi);
            result = eval(util.valToString(original));
            testCase.verifyEqual(result, original);
        end

    end

end