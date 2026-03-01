function [desc, dll, c] = buildDLL(modelIn, nvp)
arguments
    modelIn (1,1) string
    nvp.SkipBuild (1,1) logical = false % 
    nvp.PreserveWrapper (1,1) logical = true
    nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.Verbose (1,1) logical = true
    nvp.WrapSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
    nvp.ParameterConfigFile (1,1) string = NaN
end

% Load the model and ensure the correct target is selected
model = modelIn;
[~, cModel] = util.loadSystem(model); 

stf = get_param(model, "SystemTargetFile");
if stf ~= "cigre.tlc"
    error("Target must be cigre.tlc")
end

% Ensure the wrapper suffix is different from model name as this can cause 
% issues processing the name
wrapSuffix = nvp.WrapSuffix;
if contains(model, wrapSuffix)
    error("Wrap suffix " + wrapSuffix + " clashes with the model " + model);   
end
 
% Produce a wrapper to deal with buses
if nvp.PreserveWrapper
    wrapper = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType);
    cWrap = [];
else 
    [wrapper, cWrap] = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType); 
end

% Set the global codegen folder before build - Simulink's build system reads
% this from global state and it cannot be passed directly
codeGenFolder = nvp.CodeGenFolder;
if ~isfolder(codeGenFolder)
    mkdir(codeGenFolder);
end
cfg = Simulink.fileGenControl('getConfig');
cfg.CodeGenFolder = codeGenFolder;
Simulink.fileGenControl('setConfig', 'config', cfg, 'createDir', true);


% Write build context so the cigre_make_rtw_hook can access options
buildContext.ParameterConfigFile = nvp.ParameterConfigFile;
contextPath = fullfile(codeGenFolder, "cigre_build_context.mat");
save(contextPath, "-struct", "buildContext");
cleanupContext = onCleanup(@() deleteIfExists(contextPath));

if ~nvp.SkipBuild
    cigre.internal.build(wrapper);
else
    % Generate code without compiling, so the hook still fires and
    % produces the CIGRE source, but make is not invoked
    cigre.internal.buildCodeOnly(wrapper);
end

% Analyse the model after the build so buildDLL can return the description.
% The hook has already run analyseModel internally, but ModelDescription is
% a handle object and cannot be passed through the build system boundary,
% so a second call is necessary here.
desc = cigre.description.ModelDescription.analyseModel(model, wrapper, ...
    "CodeGenFolder", codeGenFolder);

           
dll = model + "_CIGRE";
c = [];

if nvp.Verbose
    disp("CIGRE compatible DLL created for model " + model + ". This can be found " + codeGenFolder);
end

% Output cleanup objects if requests to stop auto cleanup of wrapper
if nargout > 2
    c = {cModel, cWrap};
end

end

function deleteIfExists(path)
    if isfile(path)
        delete(path);
    end
end