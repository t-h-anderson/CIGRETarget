function ModelName = getAllTestModels()

root = cigreRoot();
modelsFld = fullfile(root, "test", "models");

mdls = dir(fullfile(modelsFld, "**", "*.slx"));
mdls = erase(string({mdls(:).name}), ".slx");

% Add the models to the path
pths = genpath(modelsFld);
c = onCleanup(@() rmpath(pths));
addpath(pths);

warning("off");
refs = cell(1, numel(mdls));
for ii = 1:numel(mdls)
    mdl = mdls(ii);
    
    try
        refs{ii} = find_mdlrefs(mdl, "ReturnTopModelAsLastElement", false, "KeepModelsLoaded", true);
    catch me
        % Mark as model ref so it is removed
        refs{ii} = mdl;
        disp("Skipping " + mdl + " because of error: " + me.message);
    end
    
    if isempty(refs{ii})
        refs{ii} = reshape(refs{ii}, [], 1);
    end
end
warning("on");
refs = unique(vertcat(refs{:}));

idx = ismember(mdls, refs);

tf = arrayfun(@(x) isLibrary(x), mdls);

bdclose(mdls);

ModelName = mdls(~idx & ~tf);

ModelName = num2cell(reshape([ModelName; ModelName], 1, []));

ModelName = struct(ModelName{:});

end

function tf = isLibrary(mdl)
try
    tf = bdIsLibrary(mdl);
catch me
    disp(me.message);
    tf = true;
end

end

