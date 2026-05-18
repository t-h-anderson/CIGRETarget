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

            % R2020b's find_system rejects strings for these on/off
            % values ("Option 'FollowLinks' must have a value of 'on',
            % 'off' or be a logical scalar"); use char literals.
            scans = struct( ...
                'BlockType', "TriggerPort", ...
                'Predicate', @(b) string(get_param(b, "InitialTriggerSignalState")) == "compatibility (no trigger on first evaluation)", ...
                'FindOpts', {{'FollowLinks', 'on', 'LookUnderMasks', 'on'}});

            cigre.advisor.common.CustomCheck.reportFromBlockScan(checkObj, model, scans, ...
                "Check that no trigger blocks have initial trigger signal state set to compatibility mode.", ...
                "No trigger blocks using compatibility mode found.", ...
                "The following blocks have compatibility mode set:", ...
                "Set the blocks initial trigger signal state to zero, positive or negative.");
        end
    end
end