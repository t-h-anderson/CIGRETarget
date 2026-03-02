
function advisorChecks()

checkIDs = {'cigre.configset.cigre_0001','cigre.virtualbus.cigre_0002','cigre.interfacetypes.cigre_0003','cigre.trig_ss.cigre_0004'};
passModels = {'configset_0001_pass','virtualbus_0002_pass','interfacetypes_0003_pass','triggered_ss_0004_pass'};
failModels = {'configset_0001_fail','virtualbus_0002_fail','interfacetypes_0003_fail','triggered_ss_0004_fail'};
nrFails = 0;
for idx=1:numel(checkIDs)

% Test pass model
try
    fprintf('Running %s on %s.slx =====> ', checkIDs{idx}, passModels{idx});
    res = ModelAdvisor.run(passModels{idx},checkIDs{idx}, 'DisplayResults', 'None', 'Force', 'on');
    if strcmp(res{1}.CheckResultObjs.status, 'Pass')
        fprintf(' PASS\n');
    else
        nrFails = nrFails + 1;
        fprintf(' FAIL ***\n');
    end
catch me
    fprintf('EXCEPTION\n');
end


% Test fail model
try
    fprintf('Running %s on %s.slx =====> ', checkIDs{idx}, failModels{idx});
    res = ModelAdvisor.run(failModels{idx},checkIDs{idx}, 'DisplayResults', 'None', 'Force', 'on');
    if verLessThan("MATLAB", "23.2")
        comp = 'Warning';
    else
        comp = 'Fail';
    end
    if strcmp(res{1}.CheckResultObjs.status, comp) %
        fprintf(' PASS\n');
    else
        fprintf(' FAIL ***\n');
        nrFails = nrFails + 1;
    end
catch me
    fprintf('EXCEPTION\n');
end

end

fprintf('\n##### Total number of failed tests: %d\n\n', nrFails);

end
