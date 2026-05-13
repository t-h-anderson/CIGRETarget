% Resolve all paths relative to this script so the suite can be invoked
% from any working directory (e.g. via run('test/runAllTests.m') which
% cd's into test/ before executing).
here = fileparts(mfilename("fullpath"));
projectRoot = fullfile(here, "..");
openProject(projectRoot);

% Ensure the test parent is on the path so the +test package and its
% subpackages are reachable. openProject usually does this, but on older
% releases the project may load without applying its path entries; doing
% it explicitly here keeps discovery release-independent.
addpath(here);

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.XMLPlugin
import matlab.unittest.plugins.TAPPlugin
import matlab.unittest.plugins.ToFile
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoberturaFormat
import matlab.unittest.selectors.HasTag

% Discover via package rather than folder: TestSuite.fromFolder's
% handling of +package/ subfolders has varied across MATLAB releases and
% returned an empty suite on R2020b in CI. Package-based discovery is
% explicit about what's being searched.
suite = TestSuite.fromPackage("test", "IncludingSubpackages", true);
% Manual-tagged tests (e.g. tVSBuild) exist to be invoked from MATLAB
% with a debugger attached; exclude them from the unattended CI run.
suite = suite.selectIf(~HasTag("Manual"));

% Fail loudly if discovery returned nothing; an empty suite would
% otherwise be reported as a successful run with zero tests.
if isempty(suite)
    error("runAllTests:NoTestsFound", ...
        "No tests discovered under the 'test' package. Check that '%s' is on the MATLAB path.", here);
end

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
