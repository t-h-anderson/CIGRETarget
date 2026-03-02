classdef tPadToBoundary < matlab.unittest.TestCase
    % Unit tests for util.padToBoundary.
    %
    % padToBoundary pads a row vector with trailing zeros so that its
    % length is a multiple of the requested boundary size. This is used
    % during DLL data packing to ensure each typed value starts at a
    % naturally-aligned byte offset.

    methods (Test)

        % --- No-op cases ---------------------------------------------------

        function alreadyAlignedReturnsUnchanged(testCase)
            % Input whose length is already a multiple of the boundary
            % should be returned unchanged, with no padding appended.
            input = uint8([1, 2, 3, 4]);
            result = util.padToBoundary(input, 4);
            testCase.verifyEqual(result, input);
        end

        function emptyInputWithBoundaryOneReturnsEmpty(testCase)
            result = util.padToBoundary(uint8([]), 1);
            testCase.verifyEqual(result, uint8(zeros(1,0)));
        end

        function boundaryOneNeverPads(testCase)
            % Any array is trivially aligned to a boundary of 1.
            input = uint8([10, 20, 30]);
            result = util.padToBoundary(input, 1);
            testCase.verifyEqual(result, input);
        end

        % --- Padding cases -------------------------------------------------

        function oneByteshortGetsPadded(testCase)
            % A three-element array padded to a boundary of 4 should
            % become four elements with a trailing zero.
            input = uint8([1, 2, 3]);
            result = util.padToBoundary(input, 4);
            testCase.verifyEqual(result, uint8([1, 2, 3, 0]));
        end

        function twoBytesShortGetsPadded(testCase)
            input = uint8([1, 2]);
            result = util.padToBoundary(input, 4);
            testCase.verifyEqual(result, uint8([1, 2, 0, 0]));
        end

        function threeBytesShortGetsPadded(testCase)
            input = uint8([5]);
            result = util.padToBoundary(input, 4);
            testCase.verifyEqual(result, uint8([5, 0, 0, 0]));
        end

        function paddingDoesNotExceedOneBoundaryWidth(testCase)
            % Padding should bring the length up to the next multiple,
            % never add a full extra boundary width when already aligned.
            input = uint8([1, 2, 3, 4, 5, 6, 7, 8]);
            result = util.padToBoundary(input, 4);
            testCase.verifyEqual(numel(result), 8);
        end

        % --- Output shape --------------------------------------------------

        function outputIsAlwaysRowVector(testCase)
            input = uint8([1, 2, 3]);
            result = util.padToBoundary(input, 4);
            testCase.verifySize(result, [1, 4]);
        end

        % --- Boundary sizes ------------------------------------------------

        function boundaryOfEightPadsCorrectly(testCase)
            input = uint8(ones(1, 5));
            result = util.padToBoundary(input, 8);
            testCase.verifyEqual(numel(result), 8);
            testCase.verifyEqual(result(6:8), uint8([0, 0, 0]));
        end

    end

end