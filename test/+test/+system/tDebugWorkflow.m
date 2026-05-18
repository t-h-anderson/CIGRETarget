classdef tDebugWorkflow < matlab.unittest.TestCase
% tDebugWorkflow System tests for the Visual Studio debug-build workflow.
%
% Exercises the cigre.util capture utilities and the cigre.internal
% VS-project machinery on a Linux-capable path: Simulink simulation and
% CIGRE code generation, but no C compiler. The full Windows
% build-and-run loop - cigre.buildDLL(Debug=true) driving MSBuild, then
% cigre.internal.runDebugDLL hosting the DLL on a parallel worker -
% needs Visual Studio and is covered by tGenerateCigre.tVSBuild, which
% is tagged Manual.
%
% Codegen-dependent tests override the model toolchain to auto-detect
% (the saved models reference Windows-only CIGRE toolchains) and treat
% documented older-release codegen limitations as Incomplete rather
% than failures, mirroring tGenerateCigre.tBuild.

    methods (TestClassSetup)

        function copyModels(testCase)
            % Copy the test models into a working folder and add them to
            % the path, so which()/load_system resolve them regardless of
            % the per-test working directory.
            testCase.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);

            copyfile(fullfile(cigreRoot, "test", "models"), pwd);

            pths = genpath(pwd);
            testCase.addTeardown(@() rmpath(pths));
            addpath(pths);
        end

    end

    methods (TestClassTeardown)

        function closeAll(testCase) %#ok<MANU>
            bdclose("all");
            Simulink.data.dictionary.closeAll("-discard");
        end

    end

    methods (TestMethodTeardown)

        function closeModels(testCase) %#ok<MANU>
            % Several tests reuse Test_SISO; close everything between
            % methods so a model left loaded (with a toolchain override
            % or a stale wrapper) can't leak into the next test.
            bdclose("all");
            Simulink.data.dictionary.closeAll("-discard");
        end

    end

    methods (Test)

        function tCaptureInputsFromSimulink(testCase)
            % captureInputsFromSimulink sims a model and writes the
            % logged Inport signals to a .mat as a single timetable.
            testCase.useTempWorkFolder();
            outFile = fullfile(pwd, "siso_inputs.mat");

            cigre.util.captureInputsFromSimulink("Test_SISO", outFile);

            testCase.assertTrue(isfile(outFile), ...
                "captureInputsFromSimulink should write the .mat file.");

            loaded = load(outFile);
            fields = string(fieldnames(loaded));
            inputs = loaded.(fields(1));
            testCase.verifyTrue(istimetable(inputs), ...
                "The saved variable should be a timetable.");
            testCase.verifyGreaterThan(width(inputs), 0, ...
                "The captured timetable should have at least one signal.");
            testCase.verifyGreaterThan(height(inputs), 0, ...
                "The captured timetable should have at least one sample.");
        end

        function tCaptureParametersFromSimulink(testCase)
            % captureParametersFromSimulink runs codegen to enumerate the
            % model's parameters and writes a ParameterConfig.xlsx that
            % round-trips through ParameterConfiguration.fromFile.
            testCase.useTempWorkFolder();
            cleanups = test.util.setAutoToolchain("Test_CP"); %#ok<NASGU>
            outFile = fullfile(pwd, "cp_params.xlsx");

            try
                cigre.util.captureParametersFromSimulink("Test_CP", outFile, ...
                    "CodeGenFolder", string(pwd));
            catch me
                testCase.assumeFalse(test.util.isKnownReleaseLimitation(me), ...
                    "Test_CP codegen hit a documented older-release limitation: " + me.message);
                rethrow(me)
            end

            testCase.assertTrue(isfile(outFile), ...
                "captureParametersFromSimulink should write the .xlsx file.");

            config = cigre.config.ParameterConfiguration.fromFile(outFile);
            testCase.verifyNotEmpty(config.Parameters, ...
                "Test_CP exposes parameters, so the config should be non-empty.");
        end

        function tCaptureParametersRejectsNonSpreadsheet(testCase)
            % The output-extension guard rejects a non-spreadsheet target
            % up front, before the (slow) codegen pass.
            testCase.verifyError( ...
                @() cigre.util.captureParametersFromSimulink("Test_SISO", "params.mat"), ...
                "CIGRE:captureParametersFromSimulink:UnsupportedExtension");
        end

        function tGenerateInputsAndParameters(testCase)
            % generateDefaultInputs and resolveParameters derive their
            % results purely from the model description; verify the
            % shapes without a Simulink run. captureSimulinkBaseline
            % (the run-and-extract path) is covered on Windows by
            % tGenerateCigre and is deliberately not exercised here -
            % its extractData dependency does not run on CI.
            testCase.useTempWorkFolder();
            cleanups = test.util.setAutoToolchain("Test_SISO"); %#ok<NASGU>

            desc = testCase.codegenOnly("Test_SISO");

            time = seconds(0:0.1:1)';
            inputs = cigre.internal.generateDefaultInputs(desc, time);
            testCase.verifyTrue(istimetable(inputs), ...
                "generateDefaultInputs should return a timetable.");
            testCase.verifyEqual(width(inputs), numel(desc.Inputs), ...
                "One timetable variable per model Inport.");
            testCase.verifyEqual(height(inputs), numel(time), ...
                "One row per supplied time step.");

            [simParams, cigreParams] = cigre.internal.resolveParameters(desc, ...
                cigre.config.ParameterConfiguration());
            testCase.verifyTrue(isstruct(simParams), ...
                "resolveParameters should return a SimulinkParameters struct.");
            testCase.verifyTrue(isstruct(cigreParams), ...
                "resolveParameters should return a CIGREParameters struct.");
        end

        function tWriteVSProject(testCase)
            % writeVSProject emits a Debug | x64 .sln + .vcxproj that
            % lists the generated sources.
            testCase.useTempWorkFolder();
            cleanups = test.util.setAutoToolchain("Test_SISO"); %#ok<NASGU>

            testCase.codegenOnly("Test_SISO");

            slnPath = cigre.internal.writeVSProject("Test_SISO", string(pwd));

            testCase.assertTrue(isfile(slnPath), ...
                "writeVSProject should write the .sln file.");
            vcxprojPath = fullfile(pwd, "Test_SISO_CIGRE.vcxproj");
            testCase.assertTrue(isfile(vcxprojPath), ...
                "writeVSProject should write the .vcxproj file.");

            vcxproj = fileread(vcxprojPath);
            testCase.verifySubstring(vcxproj, "Debug|x64", ...
                "The project should declare the Debug|x64 configuration.");
            testCase.verifySubstring(vcxproj, "<ClCompile", ...
                "The project should list source files for compilation.");
        end

        function tFindVSInstallationErrorsOffWindows(testCase)
            % On a non-Windows runner findVSInstallation cannot locate
            % vswhere and errors cleanly; the Windows leg (where it
            % succeeds) is exercised through tGenerateCigre.tVSBuild.
            testCase.assumeFalse(ispc, ...
                "A Windows runner can locate a real VS install.");
            testCase.verifyError(@() cigre.internal.findVSInstallation(), ...
                "CIGRE:findVSInstallation:NotWindows");
        end

    end

    methods (Access = private)

        function useTempWorkFolder(testCase)
            % Fresh per-test working folder, plus a teardown that resets
            % Simulink's fileGenControl. cigre.buildDLL points the
            % code-gen / cache folders at the working directory; the
            % reset teardown is registered AFTER the WorkingFolderFixture
            % so it runs BEFORE the fixture deletes that directory.
            % Without it, fileGenControl would keep pointing at a
            % now-deleted temp path and every subsequent test (here or
            % in tGenerateCigre) would fail its Simulink.fileGenControl
            % call with RTW:buildProcess:RootFolderDoesNotExist.
            testCase.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            testCase.addTeardown(@() Simulink.fileGenControl("reset"));
        end

        function desc = codegenOnly(testCase, modelName)
            % Run cigre.buildDLL up to code generation (no make step),
            % converting documented older-release codegen limitations
            % into an Incomplete result rather than a failure.
            arguments
                testCase
                modelName (1,1) string
            end
            try
                desc = cigre.buildDLL(modelName, ...
                    "SkipBuild", true, ...
                    "CodeGenFolder", string(pwd));
            catch me
                testCase.assumeFalse(test.util.isKnownReleaseLimitation(me), ...
                    modelName + " codegen hit a documented older-release limitation: " + me.message);
                rethrow(me)
            end
        end

    end

end
