% Resolve all paths relative to this script so the suite can be invoked
% from any working directory (e.g. via run('test/runAllTests.m') which
% cd's into test/ before executing).
here = fileparts(mfilename("fullpath"));
projectRoot = fullfile(here, "..");
openProject(projectRoot);

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.XMLPlugin
import matlab.unittest.plugins.TAPPlugin
import matlab.unittest.plugins.ToFile
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoberturaFormat
import matlab.unittest.selectors.HasTag

suite = TestSuite.fromFolder(here, "IncludeSubFolders", true);
% Manual-tagged tests (e.g. tVSBuild) exist to be invoked from MATLAB
% with a debugger attached; exclude them from the unattended CI run.
suite = suite.selectIf(~HasTag("Manual"));

runner = TestRunner.withTextOutput();
resultsDir = fullfile(projectRoot, "artifacts");
% XMLPlugin and CoberturaFormat write straight into resultsDir and won't
% create it themselves, so ensure it exists before any plugin is added.
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

resultsFile = fullfile(resultsDir, "JunitXMLResults.xml");
runner.addPlugin(XMLPlugin.producingJUnitFormat(resultsFile));

coverageFile = fullfile(resultsDir, "cobertura-coverage.xml");
src = fullfile(projectRoot, "src");
runner.addPlugin(CodeCoveragePlugin.forFolder(src, "IncludingSubfolders", true, ...
    "Producing", CoberturaFormat(coverageFile)));

try
    results = assertSuccess(runner.run(suite));
    table(results)
catch e
    disp(getReport(e, "extended"));
    if batchStartupOptionUsed
        exit(1);
    end
end

% Intended for batch invocation; batchStartupOptionUsed keeps interactive
% MATLAB sessions from exiting on completion.
if batchStartupOptionUsed
    exit(any([results.Failed]))
end
