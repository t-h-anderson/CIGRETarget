function checkModel(mdl)
arguments
    mdl
end

res = ModelAdvisor.run(mdl, 'Configuration', 'CIGRE_selection.json', 'Force', 'on');
if res{1}.numFail > 0 
    fprintf('\n=====> ***** Model failed some checks see report for details!\n\n');
else
    fprintf('\n=====> Model passed all checks!\n\n');    
end

end
