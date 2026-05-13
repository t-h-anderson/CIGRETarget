classdef Cigre0001ConfigSet < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.
    %
    % Requirements
    % ============
    %
    %

    properties (Constant)
        ID = "cigre.configset.cigre_0001";
        Title = "cigre_0001 Ensure proper settings in the configuration set.";
        TitleTips = "Check configurate set.";
        Group = "CIGRE";
        Compile = "None"
    end

    properties (Constant, Hidden)
        Style = "DetailStyle"
    end

    methods (Static)
        function checkCallback(model, checkObj)
            arguments
                model (1,1) string
                checkObj
            end

            % The cigre.tlc target file enforces every other required
            % setting, so this is the only configuration to verify here.
            cs = getActiveConfigSet(model);
            stf = string(cs.get_param("SystemTargetFile"));

            invalid = stf ~= "cigre.tlc";

            description = "Check if the correct system target file is selected.";
            if invalid
                status = "The system target file is incorrect: " + stf;
                recAction = "Select the cigre.tlc system target file in the configuration set.";
                pass = false;
            else
                status = "The system target file is set correctly (cigre.tlc).";
                recAction = "";
                pass = true;
            end
            cigre.advisor.common.CustomCheck.reportResultsSimple(checkObj, model, pass, description, status, recAction);
        end
    end
end