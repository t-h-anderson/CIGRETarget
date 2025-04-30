openProject(".");

%% Importation
import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.XMLPlugin
import matlab.unittest.plugins.TAPPlugin
import matlab.unittest.plugins.ToFile
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoberturaFormat

suite = TestSuite.fromFolder(pwd,'IncludeSubFolders',true);

%% Add runner
% For command windows output
runner = TestRunner.withTextOutput();
resultsDir = 'artifacts';

%% Adding Junit Plugin
% creating the XML file path
resultsFile = fullfile(resultsDir,'JunitXMLResults.xml');
% adding the plugin to the runner
runner.addPlugin(XMLPlugin.producingJUnitFormat(resultsFile));

%% Adding Coverage 
% creating the coverage report path
coverageFile = fullfile(resultsDir, 'cobertura-coverage.xml');
% creating the path to the functions to cover
src = fullfile('src');
% adding the plugin to the runner
runner.addPlugin(CodeCoveragePlugin.forFolder(src,'IncludingSubfolders',true,...
    'Producing', CoberturaFormat(coverageFile)));

%% run tests
try
    results = assertSuccess(runner.run(suite));
    table(results)
catch e
    disp(getReport(e,'extended'));
    if batchStartupOptionUsed
        exit(1);
    end
end

% This isn't really intended to be run from MATLAB, but if you do 
% batchStartupOptionUsed stops it exiting for you.
if batchStartupOptionUsed
    exit(any([results.Failed]))
end
