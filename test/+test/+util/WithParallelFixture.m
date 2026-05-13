classdef WithParallelFixture < matlab.unittest.TestCase

    methods (Access = protected)

        function result = runParallel(testCase, func, nOut, nvp)
            arguments
                testCase (1,1)
                func (1,1) function_handle  
                nOut (1,1) double = 1
                nvp.PauseBeforeRun (1, 1) logical = false
            end

            delete(gcp("nocreate"));
            % backgroundPool runs in-process and cannot host a loaded DLL,
            % so a real parpool is required for these tests.
            p = parpool(1);
            try
                myCluster = parcluster("Processes");
            catch
                myCluster = parcluster("local");
            end

            state = warning("query", "parallel:cluster:LocalWorkerCrash").state;
            warning("off", "parallel:cluster:LocalWorkerCrash");
            testCase.addTeardown(@() warning(state, "parallel:cluster:LocalWorkerCrash"));

            testCase.addTeardown(@() delete(myCluster.Jobs));

            if nvp.PauseBeforeRun
                keyboard %#ok<KEYBOARDFUN>
            end

            f = parfeval(p, func, nOut);
            wait(f, "finished", 1000);
            % A worker crash would drop NumWorkers to 0; the assertion
            % catches DLL segfaults that would otherwise look like a hang.
            testCase.assertGreaterThan(p.NumWorkers, 0);

            result = f.fetchOutputs();

        end

    end

end

