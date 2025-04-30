classdef WithParallelFixture < matlab.unittest.TestCase

    methods (Access = protected)

        function result = runParallel(testCase, func, nOut, nvp)
            arguments
                testCase (1,1)
                func (1,1) function_handle  
                nOut (1,1) double = 1
                nvp.PauseBeforeRun (1, 1) logical = false
            end

            delete(gcp('nocreate'));
            p = parpool(1); % backgroundPool doesn't support dll loading
            myCluster = parcluster('Processes');

            state = warning("query", "parallel:cluster:LocalWorkerCrash").state;
            warning("off", "parallel:cluster:LocalWorkerCrash");
            testCase.addTeardown(@() warning(state, "parallel:cluster:LocalWorkerCrash"));

            testCase.addTeardown(@() delete(myCluster.Jobs));
            
            if nvp.PauseBeforeRun
                keyboard
            end
            
            f = parfeval(p, func, nOut);
            wait(f, "finished", 1000);
            testCase.assertGreaterThan(p.NumWorkers, 0); % If the dll seg faults, the parpool worker dies

            result = f.fetchOutputs();
            
        end

    end

end

