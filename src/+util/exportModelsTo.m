function exportModelsTo(ver)
arguments
    ver (1,1) string = "R2020a"
end

models = test.system.tGenerateCigre.ModelName;

%here = cigreRoot;

%target = fullfile(here, "test", "models_" + ver);

%mkdir(target);

for i = 1:numel(models)
    model = models{i};
   
    mdlRefs = string(find_mdlrefs(model));

    for j = 1:numel(mdlRefs)
        mdl = mdlRefs(j);

        target = fileparts(which(mdl));
        target = strrep(target, "models", "models_" + ver);
        mkdir(target);

        [~, co] = util.loadSystem(mdl); %#ok<ASGLU>

        Simulink.exportToVersion(mdl, fullfile(target, mdl), ver);
       
    end

    clear("co");

end