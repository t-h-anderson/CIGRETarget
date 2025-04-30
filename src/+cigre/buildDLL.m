function [desc, dll, c] = buildDLL(model, nvp)
arguments
    model
    nvp.SkipBuild (1,1) logical = false
    nvp.PreserveWrapper (1,1) logical = true
    nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.Verbose (1,1) logical = true
    nvp.InterWrapSuffix (1,1) string = "_iwrap"
    nvp.WrapSuffix (1,1) string = "_wrap"
end

% Load the model and ensure the correct target is selected
modelIn = model;
[~, cModel] = util.loadSystem(model); 

stf = get_param(model, "SystemTargetFile");
if stf ~= "cigre.tlc"
    error("Target must be cigre.tlc")
end

% Ensure the intermediate wrapper suffix is different from the top level
% wrapper and model as this can cause issues processing the name
intermediateWrapSuffix = nvp.InterWrapSuffix;
wrapSuffix = nvp.WrapSuffix;
if contains(wrapSuffix, intermediateWrapSuffix) ...
        || contains(intermediateWrapSuffix, wrapSuffix) ...
        || contains(model, intermediateWrapSuffix) ...
        || contains(model, wrapSuffix)
    error("Wrap suffix " + wrapSuffix + " or intermediate wrap suffix " + intermediateWrapSuffix + " clash with each other or the model " + model);   
end

% Produce an intermediate wrapper to deal with buses
if nvp.PreserveWrapper
    iWrapper = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", intermediateWrapSuffix);
    cIWrap = [];
else 
    [iWrapper, cIWrap] = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", intermediateWrapSuffix); 
end

% Wrap the wrapper to provide the standard model reference interface
[wrapper, cWrap] = cigre.internal.cigreWrap(iWrapper, "NameSuffix", wrapSuffix);
cigre.internal.build(wrapper);

desc = cigre.description.ModelDescription.analyseModel(model, iWrapper, wrapper);
           
dll = model + "_CIGRE";
c = [];

% desc = cigre.description.ModelDescription.analyseModel(model, iWrapper, wrapper);
% 
% writer = cigre.writer.CIGREWriter;
% desc.writeDLLSource(writer);
% 
% if ~nvp.SkipBuild
%     cigre.internal.buildDLL(desc);
% else
%     dll = string(missing);
%     c = [];
%     return
% end
% 
% % Move the generated dll and header to the right place
cgf = nvp.CodeGenFolder;
here = cgf;
if ~isfolder(here)
    mkdir(here);
end
% 
% % Build in code gen folder
% dll = fullfile(cgf, desc.WrapperName + ".dll");
% 
% dllDeploy = fullfile(here, modelIn + "_CIGRE.dll");
% copyfile(dll, dllDeploy);
% delete(dll);
% 
% [~, dll] = fileparts(dllDeploy);
% headerDeploy = fullfile(here, dll + ".h");
% header = fullfile(cgf, "slprj", "cigre", model + "_CIGRE" + ".h");
% 
% copyfile(header, headerDeploy);

if nvp.Verbose
    disp("CIGRE compatible DLL created for model " + model + ". This can be found " + here);
end

% Output cleanup objects if requests to stop auto cleanup of wrapper
if nargout > 2
    c = {cModel, cWrap, cIWrap};
end

