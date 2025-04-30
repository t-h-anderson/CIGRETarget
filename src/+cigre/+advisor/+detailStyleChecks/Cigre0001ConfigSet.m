classdef Cigre0001ConfigSet < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.
    %
    % Requirements
    % ============
    %
    %

    properties (Constant)
        ID = 'cigre.configset.cigre_0001';
        Title = 'cigre_0001 Ensure proper settings in the configuration set.';
        TitleTips = 'Check configurate set.';
        Group = 'CIGRE';
        Compile = "None" % ["None", "PostCompile", "PostCompileForCodegen"]
    end

    properties (Constant, Hidden)
        Style = 'DetailStyle'
    end

    methods (Static)
        function checkCallback(model, checkObj)

            % -------------------------------------------------------------
            % Get the system target file
            % This is the only thing we need to check here as the target
            % file will enforce the right settings.
            % -------------------------------------------------------------
            cs = getActiveConfigSet(model);
            stf = cs.get_param('SystemTargetFile');

            if strcmp(stf, 'cigre.tlc')
                invalid = false;
            else
                invalid = true;
            end

            % -------------------------------------------------------------
            %                     Process results
            % -------------------------------------------------------------
            description = 'Check if the correct system target file is selected.';
            if invalid
                status = ['The system target file is incorrect: ', stf];
                recAction = 'Select the cigre.tlc system target file in the configuration set.';
                pass = false;
            else
                status = 'The system target file is set correctly (cigre.tlc).';
                recAction = '';
                pass = true;
            end
            cigre.advisor.common.CustomCheck.reportResultsSimple(checkObj, model, pass, description, status, recAction);
        end
    end
end