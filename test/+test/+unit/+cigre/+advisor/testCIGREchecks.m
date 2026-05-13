classdef testCIGREchecks < matlab.unittest.TestCase

    properties (TestParameter)
        checkIDs = {"cigre.configset.cigre_0001", "cigre.virtualbus.cigre_0002", "cigre.interfacetypes.cigre_0003", "cigre.trig_ss.cigre_0004"};
        passModels = {"configset_0001_pass", "virtualbus_0002_pass", "interfacetypes_0003_pass", "triggered_ss_0004_pass"};
        failModels = {"configset_0001_fail", "virtualbus_0002_fail", "interfacetypes_0003_fail", "triggered_ss_0004_fail"};
    end

    methods (TestClassSetup)

        function setup(testCase)
            % R2020a's ModelAdvisor API does not understand the newer
            % check definitions, so test artefacts are split per release.
            if verLessThan("MATLAB", "9.9.0")
                pth = fullfile(cigreRoot(), "test", "artefacts", "advisor", "Test2020a");
            else
                pth = fullfile(cigreRoot(), "test", "artefacts", "advisor", "Test2023b");
            end

            fixture = matlab.unittest.fixtures.PathFixture(pth);

            testCase.applyFixture(fixture);
        end

    end

    methods (Test, ParameterCombination = "sequential")

        function tCheckPass(testCase, checkIDs, passModels)
            res = ModelAdvisor.run(passModels, checkIDs, "DisplayResults", "None", "Force", "on");
            status = string(res{1}.CheckResultObjs.status);
            % MathWorks renamed the status spelling across releases
            % ("Pass" pre-R2023b, "Pass" / "Passed" later); accept either.
            testCase.verifyTrue(startsWith(status, "Pass"), ...
                "Expected status to start with 'Pass' but got: " + status);
        end

        function tCheckFail(testCase, checkIDs, failModels)
            res = ModelAdvisor.run(failModels, checkIDs, "DisplayResults", "None", "Force", "on");
            status = string(res{1}.CheckResultObjs.status);
            % "Warning" pre-R2023b, "Fail" mid-range, "Failed" R2026a+.
            testCase.verifyTrue(startsWith(status, "Fail") | status == "Warning", ...
                "Expected status to start with 'Fail' or be 'Warning' but got: " + status);
        end

    end

end
