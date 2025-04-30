RTW.TargetRegistry.getInstance('reset');

% dllName = modelName  + "_wrapper";
% 
% hfile = fullfile(pwd, "slprj", modelName  + "_CIGRE.h");
% 
% src = fullfile(cigreRoot, "src", "CIGRESource");
% 
% shared = fullfile(pwd, "slprj", "cigre", "_sharedutils");
% 
% [a,b] = loadlibrary(dllName + ".dll", hfile, ...
%                     "includepath", src, ...
%                     "includepath", shared);
% 
% unloadlibrary(dllName)