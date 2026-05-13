function exportModelsTo(ver)
% exportModelsTo Deprecated alias for util.setAllModelsTo.
%
% The original exportModelsTo created a parallel models_R<ver>/ tree and
% assumed every model was on the path, which broke as soon as anyone
% invoked it from a fresh session. util.setAllModelsTo replaces the file
% in place and archives the previous version under the release tag it
% was saved at; prefer it for new work.
arguments
    ver (1,1) string = "R2020a"
end

util.setAllModelsTo(ver);
end
