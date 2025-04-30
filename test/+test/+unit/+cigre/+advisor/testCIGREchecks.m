classdef testCIGREchecks < matlab.unittest.TestCase

    properties (TestParameter)
        checkIDs = {'cigre.configset.cigre_0001','cigre.virtualbus.cigre_0002','cigre.interfacetypes.cigre_0003','cigre.trig_ss.cigre_0004'};
        passModels = {'configset_0001_pass','virtualbus_0002_pass','interfacetypes_0003_pass','triggered_ss_0004_pass'};
        failModels = {'configset_0001_fail','virtualbus_0002_fail','interfacetypes_0003_fail','triggered_ss_0004_fail'};
    end

    methods (TestClassSetup)

        function setup(testCase)
            if verLessThan("MATLAB", "9.9.0") % <2020b
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

                res = ModelAdvisor.run(passModels,checkIDs, 'DisplayResults', 'None', 'Force', 'on');
                
                testCase.verifyEqual(res{1}.CheckResultObjs.status, 'Pass');
                    
        end


        function tCheckFail(testCase, checkIDs, failModels)

                res = ModelAdvisor.run(failModels,checkIDs, 'DisplayResults', 'None', 'Force', 'on');
                
                testCase.verifyEqual(res{1}.CheckResultObjs.status, 'Fail');
                    
        end

    end

end