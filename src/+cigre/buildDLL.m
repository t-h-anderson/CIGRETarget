function [desc, dll, c] = buildDLL(modelIn, nvp)
arguments
    modelIn (1,1) string
    nvp.SkipBuild (1,1) logical = false
    nvp.PreserveWrapper (1,1) logical = true
    nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.Verbose (1,1) logical = true
    nvp.WrapSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
    nvp.ParameterConfigFile (1,1) string = string(NaN)
end

model = modelIn;
[~, cModel] = util.loadSystem(model);

stf = get_param(model, "SystemTargetFile");
if stf ~= "cigre.tlc"
    error("Target must be cigre.tlc")
end

% The wrapper name is built by suffixing the model name. If the suffix is
% already a substring of the model name we cannot distinguish wrapper from
% original during code generation.
wrapSuffix = nvp.WrapSuffix;
if contains(model, wrapSuffix)
    error("Wrap suffix " + wrapSuffix + " clashes with the model " + model);
end

if nvp.PreserveWrapper
    wrapper = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType);
    cWrap = [];
else
    [wrapper, cWrap] = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType);
end

% Simulink's build system reads the code gen folder from global state, so
% it must be set before invoking the build rather than passed in.
codeGenFolder = nvp.CodeGenFolder;
if ~isfolder(codeGenFolder)
    mkdir(codeGenFolder);
end
cfg = Simulink.fileGenControl("getConfig");
cfg.CodeGenFolder = char(codeGenFolder);
try
    Simulink.fileGenControl("setConfig", "config", cfg, "createDir", true);
catch
    % Older MATLAB releases reject 'setConfig' mid-session; the cfg
    % global will still take effect for the immediate build.
    warning("Setting the code gen folder during the build is not supported in older versions of MATLAB");
end

% The cigre_make_rtw_hook runs in a separate scope from buildDLL and cannot
% receive parameters directly; persist them to a side-channel .mat file.
buildContext = struct();
buildContext.WrapSuffix = nvp.WrapSuffix;
buildContext.ParameterConfigFile = nvp.ParameterConfigFile;
contextPath = fullfile(codeGenFolder, "cigre_build_context.mat");
save(contextPath, "-struct", "buildContext");
cleanupContext = onCleanup(@() deleteIfExists(contextPath));

if ~nvp.SkipBuild
    cigre.internal.build(wrapper);
else
    % SkipBuild: emit code via the hook without invoking the make step.
    buildModel(wrapper);
end

% analyseModel already ran inside the build hook, but ModelDescription is
% a handle object so it cannot be marshalled back across the build
% boundary; recompute it here for the return value.
desc = cigre.description.ModelDescription.analyseModel(model, wrapper, ...
    "CodeGenFolder", codeGenFolder);

dll = model + "_CIGRE";
c = [];

if nvp.Verbose
    disp("CIGRE compatible DLL created for model " + model + ". This can be found at: " + codeGenFolder);
end

if nargout > 2
    c = {cModel, cWrap};
end

end

function deleteIfExists(path)
arguments
    path (1,1) string
end
    if isfile(path)
        delete(path);
    end
end