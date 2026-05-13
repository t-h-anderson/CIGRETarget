function cigre_make_rtw_hook(hookMethod, modelName,~, ~, ~, buildArgs, buildInfo)
% CIGRE RTW build hook - called by Simulink at each stage of the RTW build.
%
% ert_make_rtw_hook(hookMethod, modelName, rtwroot, templateMakefile,
%                   buildOpts, buildArgs)
%
% hookMethod:
%   Specifies the stage of the build process.  Possible values are
%   entry, before_tlc, after_tlc, before_make, after_make and exit, etc.
%
% modelName:
%   Name of model.  Valid for all stages.
%
% rtwroot (~):
%   Reserved.
%
% templateMakefile (~):
%   Name of template makefile.  Valid for stages 'before_make' and 'exit'.
%
% buildOpts (~):
%   Valid for stages 'before_make' and 'exit', a MATLAB structure
%   containing fields
%
%   modules:
%     Char array specifying list of generated C files: model.c, model_data.c,
%     etc.
%
%   codeFormat:
%     Char array containing code format: 'RealTime', 'RealTimeMalloc',
%     'Embedded-C', and 'S-Function'
%
%   noninlinedSFcns:
%     Cell array specifying list of non-inlined S-Functions.
%
% buildArgs:
%   Char array containing the argument to make_rtw.  When pressing the build
%   button through the Configuration Parameter Dialog, buildArgs is taken
%   verbatim from whatever follows make_rtw in the make command edit field.
%   From MATLAB, it's whatever is passed into make_rtw.  For example, its
%   'optimized_fixed_point=1' for make_rtw('optimized_fixed_point=1').
%
%   This file implements these buildArgs:
%     optimized_fixed_point=1
%     optimized_floating_point=1
%
%
% Stages and what this hook does at each:
%   entry       - optionally auto-configure model for fixed/floating-point optimisation
%   before_make - generate CIGRE wrapper C source and configure build paths/sources
%   after_make  - rename and deploy the compiled DLL and header to output locations
%   exit        - log completion message
%   error       - log build failure message

switch string(hookMethod)
    case "error"
        msg = DAStudio.message("RTW:makertw:buildAborted", modelName);
        disp(msg);
    case "entry"
        msg = DAStudio.message("RTW:makertw:enterRTWBuild", modelName);
        disp(msg);

        option = LocalParseArgList(buildArgs);
        if option ~= "none"
            ert_unspecified_hardware(modelName);
            cs = getActiveConfigSet(modelName);
            cscopy = cs.copy;
            ert_auto_configuration(modelName, option);
            locReportDifference(cscopy, cs);
        end

    case "before_tlc"

    case "after_tlc"

    case "before_make"
        handleBeforeMake(modelName, buildInfo);

    case "after_make"
        handleAfterMake(modelName);

    case "exit"
        if string(get_param(modelName, "GenCodeOnly")) == "off"
            msgID = "RTW:makertw:exitRTWBuild";
        else
            msgID = "RTW:makertw:exitRTWGenCodeOnly";
        end
        msg = DAStudio.message(msgID, modelName);
        disp(msg);
end

end


function option = LocalParseArgList(args)
% Recognise the two supported make_rtw buildArgs:
%   optimized_fixed_point=1
%   optimized_floating_point=1
if contains(args, "optimized_fixed_point=1")
    option = "optimized_fixed_point";
elseif contains(args, "optimized_floating_point=1")
    option = "optimized_floating_point";
else
    option = "none";
end

end

function locReportDifference(cs1, cs2)
% Report any configuration-set differences introduced by ert_auto_configuration.
[iseq, diffs] = slprivate("diff_config_sets", cs1, cs2, "string");
if ~iseq
    msg = DAStudio.message("RTW:makertw:incompatibleParamsUpdated", diffs);
    summary = DAStudio.message("RTW:makertw:autoconfigSummary");
    rtwprivate("rtw_disp_info", ...
        get_param(cs2.getModel, "Name"), ...
        summary, ...
        msg);
end

end


function buildContext = loadBuildContext(codeGenFolder)
% Load build options written by buildDLL before invoking slbuild.
% buildDLL serialises options to a .mat file because the hook has no
% direct parameter channel from user code.
contextPath = fullfile(codeGenFolder, "cigre_build_context.mat");
if isfile(contextPath)
    buildContext = load(contextPath);
else
    buildContext = struct();
end
end

function handleBeforeMake(modelName, buildInfo)

here = Simulink.fileGenControl("getConfig").CodeGenFolder;
buildContext = loadBuildContext(here);

% Generate CIGRE C source and configure build paths, but only for
% CIGRE wrapper models identified by the configured wrapSuffix.
wrapSuffix = getFieldOrDefault(buildContext, "WrapSuffix", "_wrap");
if ~endsWith(modelName, wrapSuffix)
    return
end

wrapperName = modelName;
modelName = erase(wrapperName, wrapSuffix + textBoundaryPattern);
buildDir = fullfile(here, "slprj", "cigre");

replaceRtwTypes(buildDir);
paramConfig = loadParameterConfig(buildContext);
generateCigreSource(modelName, wrapperName, paramConfig);
configureBuildPaths(buildInfo, buildDir, modelName);
end


function replaceRtwTypes(buildDir)
% Replace the Simulink-generated rtwtypes.h with the CIGRE-compatible
% version to resolve type definition conflicts at link time.
replacement = fullfile(cigreRoot, "src", "CIGRESource", "rtwtypes.h");
sharedUtils = fullfile(buildDir, "_sharedutils");
copyfile(replacement, sharedUtils);
end


function paramConfig = loadParameterConfig(buildContext)
% Load the ParameterConfiguration from the file path stored in the build
% context. Returns an empty (all-visible) config if no file was specified.
paramConfig = cigre.config.ParameterConfiguration();
hasFile = isfield(buildContext, "ParameterConfigFile") ...
    && ~ismissing(buildContext.ParameterConfigFile) ...
    && isfile(buildContext.ParameterConfigFile);
if hasFile
    paramConfig = cigre.config.ParameterConfiguration.fromFile(...
        buildContext.ParameterConfigFile);
end
end


function generateCigreSource(modelName, wrapperName, paramConfig)
% Analyse the generated model code and write the CIGRE wrapper C source.
try
    desc = cigre.description.ModelDescription.analyseModel(modelName, wrapperName);
catch me
    error("Error building model description: " + me.message);
end
try
    desc.writeDLLSource(cigre.writer.CIGREWriter, "ParameterConfig", paramConfig);
catch me
    error("Error writing DLL source: " + me.message);
end
end


function configureBuildPaths(buildInfo, buildDir, modelName)
% Add CIGRE-specific include paths and source files so the compiler can
% find the generated wrapper and the CIGRE runtime support files.
sourceRoot = fullfile(cigreRoot, "src", "CIGRESource");

existingIncludes = string(buildInfo.getIncludePaths(false))';
buildInfo.addIncludePaths([existingIncludes; sourceRoot; buildDir]);

src = [fullfile(buildDir, modelName + "_CIGRE.c"), ...
    fullfile(sourceRoot, "heap.c"), ...
    fullfile(sourceRoot, "CIGRE_Defaults.c")];
buildInfo.addSourceFiles(src);
end


function handleAfterMake(modelName)

here = Simulink.fileGenControl("getConfig").CodeGenFolder;
buildContext = loadBuildContext(here);

% Rename the compiled wrapper DLL to the CIGRE output name and copy the
% header alongside it, so both are ready for distribution together.
wrapSuffix = getFieldOrDefault(buildContext, "WrapSuffix", "_wrap");
if ~endsWith(modelName, wrapSuffix)
    return
end

wrapperName = modelName;
modelName = erase(wrapperName, wrapSuffix + textBoundaryPattern);

dll = fullfile(here, wrapperName + ".dll");
if ~isfile(dll)
    % Normal when SkipBuild was requested - nothing to deploy
    return
end

dllDeploy = fullfile(here, modelName + "_CIGRE.dll");
copyfile(dll, dllDeploy);
delete(dll);

[~, deployedDllName] = fileparts(dllDeploy);
header = fullfile(here, "slprj", "cigre", modelName + "_CIGRE.h");
headerDeploy = fullfile(here, deployedDllName + ".h");
copyfile(header, headerDeploy);

disp("CIGRE DLL for model '" + modelName + "' deployed to: " + here);
end


function value = getFieldOrDefault(s, field, default)
% Return s.(field) if present, otherwise return default.
if isfield(s, field)
    value = s.(field);
else
    value = default;
end
end
