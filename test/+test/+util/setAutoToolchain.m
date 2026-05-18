function cleanups = setAutoToolchain(modelName)
% setAutoToolchain Switch the top model and every referenced submodel
% to auto-detected toolchain. Returns an array of onCleanup objects
% that keep the affected systems loaded for the lifetime of the test;
% releasing them lets bdclose run unimpeded at teardown.
%
% The saved test models reference Windows-only CIGRE toolchains (e.g.
% "CIGRE DLL - Microsoft Visual C++ 2019 ...") which aren't in the
% registry on a Linux runner; codegen there needs the toolchain
% overridden to auto-detect. Shared by the system test classes that
% drive cigre.buildDLL.
arguments
    modelName (1,1) string
end

[~, cTop] = util.loadSystem(modelName);
overrideToolchain(modelName);

refs = string(find_mdlrefs(modelName));
cleanups = {cTop};
for i = 1:numel(refs)
    if refs(i) == modelName
        continue
    end
    [~, cRef] = util.loadSystem(refs(i));
    overrideToolchain(refs(i));
    cleanups{end+1} = cRef; %#ok<AGROW>
end
end


function overrideToolchain(modelName)
% Apply the auto-detect override, then clear the dirty flag so the
% wrapper's save_system isn't blocked by SaveSystemWithDirtyReferencedModels.
% The in-memory override still takes effect; we just don't want Simulink
% to think the file on disk needs rewriting.
%
% When the model's active config is a reference (Simulink.ConfigSetRef),
% set_param on the model name fails with ConfigSetRef_SetParamNotAllowed;
% reach through to the underlying Simulink.ConfigSet and update there
% instead. Several models in test/models/ (NestedBus, Test_CP*) use this
% shape because they share a referenced config set with their submodels.
cs = getActiveConfigSet(modelName);
if ~isa(cs, "Simulink.ConfigSet")
    cs = cs.getRefConfigSet();
end
set_param(cs, "Toolchain", "Automatically locate an installed toolchain");

% UpdateModelReferenceTargets is being removed in a future release;
% MATLAB warns at every build when the saved value is anything other
% than "IfOutOfDate". Normalise it now so CI logs aren't full of the
% deprecation warning.
try
    set_param(cs, "UpdateModelReferenceTargets", "IfOutOfDate");
catch
    % Parameter or value missing on older releases - safe to skip.
end

set_param(modelName, "Dirty", "off");
end
