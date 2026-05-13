classdef Cigre0004TrigerSubsystem < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.

    properties (Constant)
        ID = "cigre.trig_ss.cigre_0004";
        Title = "cigre_0004 Ensure trigger ports initial trigger signal state is not set to compatibility mode.";
        TitleTips = "Trigger ports mode.";
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

            violatingBlocks = {};
            blks = find_system(model, "FollowLinks", "on", ...
                "LookUnderMasks", "on", "BlockType", "TriggerPort");
            for idx = 1:numel(blks)
                triggerMode = string(get_param(blks{idx}, "InitialTriggerSignalState"));
                if triggerMode == "compatibility (no trigger on first evaluation)"
                    violatingBlocks{end+1} = blks{idx}; %#ok<AGROW>
                end
            end

            description = "Check that no trigger blocks have initial trigger signal state set to compatibility mode.";
            statusPass = "No trigger blocks using compatibility mode found.";
            statusFail = "The following blocks have compatibility mode set:";
            recAction = "Set the blocks initial trigger signal state to zero, positive or negative.";
            violationType = "fail";

            cigre.advisor.common.CustomCheck.reportResults(checkObj, model, violationType, violatingBlocks, description, statusPass, statusFail, recAction);
        end
    end
end