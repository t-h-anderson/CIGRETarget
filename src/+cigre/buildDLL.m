function [desc, dll, c] = buildDLL(modelIn, nvp)
arguments
    modelIn
    nvp.SkipBuild (1,1) logical = false
    nvp.PreserveWrapper (1,1) logical = true
    nvp.CodeGenFolder (1,1) string = Simulink.fileGenControl('getConfig').CodeGenFolder
    nvp.BusAs (1,1) string {mustBeMember(nvp.BusAs, ["Ports", "Vector"])} = "Vector"
    nvp.Verbose (1,1) logical = true
    nvp.WrapSuffix (1,1) string = "_wrap"
    nvp.VectorDataType (1,1) string = "single"
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

% Produce an intermediate wrapper to deal with buses
if nvp.PreserveWrapper
    wrapper = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType);
    cWrap = [];
else 
    [wrapper, cWrap] = cigre.internal.cigreWrap(model, "BusAs", nvp.BusAs, "NameSuffix", wrapSuffix, "VectorDataType", nvp.VectorDataType); 
end

cigre.internal.build(wrapper);

desc = cigre.description.ModelDescription.analyseModel(model, wrapper);
           
dll = model + "_CIGRE";
c = [];

% % Move the generated dll and header to the right place
cgf = nvp.CodeGenFolder;
here = cgf;
if ~isfolder(here)
    mkdir(here);
end

if nvp.Verbose
    disp("CIGRE compatible DLL created for model " + model + ". This can be found " + here);
end

% Output cleanup objects if requests to stop auto cleanup of wrapper
if nargout > 2
    c = {cModel, cWrap};
end

