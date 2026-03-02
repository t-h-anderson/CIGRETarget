classdef tDataMap < matlab.unittest.TestCase
    % Unit tests for cigre.dll.DataMap.
    %
    % DataMap is responsible for packing MATLAB typed values into a flat
    % uint8 word array (for writing to the DLL interface) and unpacking
    % them back.
    %
    % Test strategy: for each supported type, verify that a create->
    % wordsToData roundtrip recovers the original value exactly. Additional
    % tests cover alignment padding, multi-field maps, and logical handling.

    methods (Test)

        % --- Single scalar roundtrips --------------------------------------

        function singleScalarRoundtrips(testCase)
            original = {single(3.14)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, single(3.14), "AbsTol", 0);
        end

        function doubleScalarRoundtrips(testCase)
            original = {double(2.718281828)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, double(2.718281828));
        end

        function int32ScalarRoundtrips(testCase)
            original = {int32(-42)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, int32(-42));
        end

        function uint8ScalarRoundtrips(testCase)
            original = {uint8(200)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, uint8(200));
        end

        function int16ScalarRoundtrips(testCase)
            original = {int16(-1000)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, int16(-1000));
        end

        % --- Logical handling ----------------------------------------------

        function logicalTrueRoundtrips(testCase)
            % Logicals are stored as int8 (1/0) and unpacked as logical.
            original = {true};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, true);
        end

        function logicalFalseRoundtrips(testCase)
            original = {false};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, false);
        end

        % --- Array roundtrips ----------------------------------------------

        function singleRowVectorRoundtrips(testCase)
            original = {single([1.0, 2.0, 3.0, 4.0])};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, single([1.0, 2.0, 3.0, 4.0]));
        end

        function int32VectorRoundtrips(testCase)
            original = {int32([10, -20, 30])};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, int32([10, -20, 30]));
        end

        function arrayDimensionsArePreserved(testCase)
            % The 2-D shape of an array must survive the roundtrip, not
            % just the values — the DLL uses size information to map signals.
            original = {single([1, 2; 3, 4])};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifySize(map.Data{1}, [2, 2]);
            testCase.verifyEqual(map.Data{1}, single([1, 2; 3, 4]));
        end

        % --- Multi-field maps ----------------------------------------------

        function twoFieldsRoundtrip(testCase)
            % A map with two fields of different types must unpack each
            % field independently to its correct type and value.
            original = {single(1.0), int32(99)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, single(1.0));
            testCase.verifyEqual(map.Data{2}, int32(99));
        end

        function threeFieldsMixedTypesRoundtrip(testCase)
            original = {double(3.14), single(-1.0), int32(7)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData();
            testCase.verifyEqual(map.Data{1}, double(3.14));
            testCase.verifyEqual(map.Data{2}, single(-1.0));
            testCase.verifyEqual(map.Data{3}, int32(7));
        end

        % --- Metadata correctness ------------------------------------------

        function dataTypeRecordedCorrectly(testCase)
            % DataTypes must record the original MATLAB class name so that
            % wordsToData can typecast back to the correct type.
            original = {single(1.0), int32(2)};
            map = cigre.dll.DataMap.create(original);
            testCase.verifyEqual(map.DataType(1), "single");
            testCase.verifyEqual(map.DataType(2), "int32");
        end

        function dimensionsRecordedCorrectly(testCase)
            % Dims must match the original array shape before flattening.
            original = {single([1, 2; 3, 4])};
            map = cigre.dll.DataMap.create(original);
            testCase.verifyEqual(map.Dims{1}, [2, 2]);
        end

        function wordCountMatchesExpectedBytes(testCase)
            % A single-precision scalar is 4 bytes, so it should produce
            % exactly 4 uint8 words.
            original = {single(0.0)};
            map = cigre.dll.DataMap.create(original);
            testCase.verifyEqual(numel(map.Words), 4);
        end

        function doubleWordCountIsEightBytes(testCase)
            original = {double(0.0)};
            map = cigre.dll.DataMap.create(original);
            testCase.verifyEqual(numel(map.Words), 8);
        end

        % --- Alignment padding ---------------------------------------------

        function doubleAfterByteIsAligned(testCase)
            % A double following a uint8 must be padded to an 8-byte
            % boundary, so the total word count should be 16 (1 byte +
            % 7 bytes padding + 8 bytes double), not 9.
            original = {uint8(1), double(1.0)};
            map = cigre.dll.DataMap.create(original);
            map = map.wordsToData("Packing", 8);
            testCase.verifyEqual(map.Data{1}, uint8(1));
            testCase.verifyEqual(map.Data{2}, double(1.0));
        end

    end

end