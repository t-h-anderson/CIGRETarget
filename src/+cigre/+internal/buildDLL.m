function buildDLL(desc)
% Generates the dll by building the top level wrapper model with the
% correct included files
arguments
    desc (1,1) cigre.description.ModelDescription
end

wrapper = desc.CIGREInterfaceName;
modelName = desc.ModelName;

here = Simulink.fileGenControl('getConfig').CodeGenFolder; % TODO: This isn't good for testing. Inject location?
buildDir = fullfile(here, "slprj", "cigre");

% Remove the stale rtwtypes
replacement = fullfile(cigreRoot, "src", "CIGRESource", "rtwtypes.h");
rtwTypes = fullfile(buildDir, "_sharedutils");
copyfile(replacement, rtwTypes)

% Update the parameters to build the dll
set_param(wrapper, "GenCodeOnly", false)

% Include directories from build info
buildInfo = load(fullfile(here, wrapper + "_cigre_rtw", 'buildInfo.mat')).buildInfo;

inc = string(buildInfo.getIncludePaths(true))';
inc = [inc; fullfile(cigreRoot, "src", "CIGRESource")]; % Custom CIGRE code
inc = """" + inc + """";
inc = strjoin(inc, newline);
set_param(wrapper, "CustomInclude", inc);

% Add custom source code needed for DLL
src = [fullfile(buildDir, modelName + "_CIGRE.c"), ...
    fullfile(cigreRoot, "src", "CIGRESource", "heap.c"),  ...
    fullfile(cigreRoot, "src", "CIGRESource", "CIGRE_Defaults.c")];
src = """" + src + """";
src = strjoin(src, newline);

set_param(wrapper, "CustomSource", src);
set_param(wrapper, "GenCodeOnly", false);

save_system(wrapper);

cigre.internal.build(wrapper);

end

