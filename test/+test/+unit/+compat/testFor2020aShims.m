classdef testFor2020aShims < matlab.unittest.TestCase
    % Exercise the legacy branches of the src/For2020a/ shims on
    % releases where verLessThan("MATLAB", "9.9") returns false. The
    % shims accept an explicit LegacyMatlab=true NV-pair that forces
    % the legacy path; without that seam the CI matrix (R2020b = 9.9,
    % strict inequality) would never enter the older code.

    methods (Test)

        function tExtractStringLegacyNumeric(testCase)
            % Legacy branch indexes into the underlying char vector;
            % modern branch defers to MATLAB's extract().
            val = extractString({'hello world'}, 4, "LegacyMatlab", true);
            testCase.verifyEqual(val, 'l');
        end

        function tExtractStringLegacyPatternRejected(testCase)
            % Pattern-based extract is unsupported on the legacy path.
            % The shim raises an identifier-less error("...") so match
            % any MException.
            testCase.verifyError( ...
                @() extractString("hello", textBoundary, "LegacyMatlab", true), ...
                ?MException);
        end

        function tFindLineStartTextLegacyMatchesModern(testCase)
            % regexp("^foo") and contains(lineBoundary + "foo") should
            % agree on a representative set of inputs.
            txt = ["foo bar"; " foo baz"; "foobar"; "no match"];
            toMatch = "foo";

            [idxsLegacy, idxLegacy] = findLineStartText(txt, toMatch, "LegacyMatlab", true);
            [idxsModern, idxModern] = findLineStartText(txt, toMatch, "LegacyMatlab", false);

            testCase.verifyEqual(logical(idxLegacy(:)), idxModern(:));
            testCase.verifyEqual(idxsLegacy, idxsModern);
        end

        function tReadFromFileLegacyMatchesModern(testCase)
            tmpFile = [tempname, '.txt'];
            cleanup = onCleanup(@() delete(tmpFile)); %#ok<NASGU>
            expected = ["alpha"; "beta"; "gamma"];
            % writelines is R2022a+ so write manually to keep the
            % fixture release-portable.
            fid = fopen(tmpFile, 'w');
            for ii = 1:numel(expected)
                fprintf(fid, "%s\n", expected(ii));
            end
            fclose(fid);

            legacy = readFromFile(tmpFile, "LegacyMatlab", true);
            modern = readFromFile(tmpFile, "LegacyMatlab", false);

            % readlines preserves the trailing empty line that follows
            % the final newline; the legacy fopen/fgetl loop does not.
            % Compare on the non-empty content only.
            testCase.verifyEqual(legacy, expected);
            testCase.verifyTrue(all(ismember(expected, modern)));
        end

        function tReadFromFileLegacyMissingFile(testCase)
            % Legacy branch returns "" when fopen fails.
            missing = readFromFile("/no/such/file/here.txt", "LegacyMatlab", true);
            testCase.verifyEqual(missing, "");
        end

        function tTextBoundaryPatternLegacy(testCase)
            % The legacy branch substitutes an empty string for the
            % textBoundary pattern (so concatenations still work).
            testCase.verifyEqual(textBoundaryPattern("LegacyMatlab", true), "");
        end

        function tWriteToFileLegacy(testCase)
            tmpFile = [tempname, '_legacy.txt'];
            cleanup = onCleanup(@() delete(tmpFile)); %#ok<NASGU>

            text = ["alpha"; "beta"; "gamma"];
            writeToFile(text, tmpFile, "LegacyMatlab", true);

            % readlines is R2020b+ so this works on every release in the
            % CI matrix. writelines (the modern branch of writeToFile)
            % is R2022a+ and would error on R2020b, so verify only the
            % legacy path here.
            legacyContent = readlines(tmpFile);
            testCase.verifyTrue(all(ismember(text, legacyContent)));
        end

        function tWriteToFileModern(testCase)
            % writelines was introduced in R2022a (9.12); silent return
            % on older releases avoids a hard error from the modern
            % branch and avoids the Incomplete-status uncertainty that
            % assumeFalse can introduce in this test harness.
            if verLessThan("MATLAB", "9.12") %#ok<VERLESSMATLAB>
                return
            end

            tmpFile = [tempname, '_modern.txt'];
            cleanup = onCleanup(@() delete(tmpFile)); %#ok<NASGU>

            text = ["alpha"; "beta"; "gamma"];
            writeToFile(text, tmpFile, "LegacyMatlab", false);

            modernContent = readlines(tmpFile);
            testCase.verifyTrue(all(ismember(text, modernContent)));
        end

        function tCompatLegacyMatlabRespectsThreshold(testCase)
            % compat.legacyMatlab defaults to the 9.9 threshold but
            % accepts an explicit version for the writeToFile gate.
            testCase.verifyEqual( ...
                compat.legacyMatlab("0"), false, ...
                "Pre-MATLAB-zero must be false on any real release.");
            testCase.verifyEqual( ...
                compat.legacyMatlab("99"), true, ...
                "Pre-MATLAB-99 must be true on any real release.");
        end

    end

end
