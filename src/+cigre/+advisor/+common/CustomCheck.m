classdef CustomCheck < handle
    % Copyright 2024 The MathWorks, Inc.
    %
    % Custom Check Super Class
    % ========================
    % This is the super class for implementing custom Model Advisor checks.
    % Use the template class or copy an existing check and modify.
    %
    % Adds new:      Advisor.Manager.refresh_customizations()
    % Refreshed all: Advisor.Manager.update_customizations()

    properties (Constant, Abstract)
        ID
        Title
        TitleTips
        Group
        Compile (1,1) string {mustBeMember(Compile, ["None", "PostCompile", "PostCompileForCodegen"])}
    end

    properties (Abstract, Constant, Hidden)
        % Callback function styles:
        % https://www.mathworks.com/help/slcheck/ref/modeladvisor.check.setcallbackfcn.html
        Style (1,:) string
    end


    methods
        function obj = CustomCheck()

            % The ModelAdvisor.Check API on older releases (notably
            % R2020b) rejects MATLAB strings for these property values
            % - the addItem/publish path internally requires character
            % vectors. char() at the boundary keeps the class-level
            % declarations expressive while still satisfying the API.
            rec = ModelAdvisor.Check(char(obj.ID));
            rec.Title = char(obj.Title);
            rec.TitleTips = char(obj.TitleTips);
            rec.CallbackContext = char(obj.Compile);
            rec.setCallbackFcn(@(system, checkObj) obj.checkCallback(system, checkObj), char(obj.Compile), char(obj.Style));
            rec.CallbackStyle = char(obj.Style);

            mdladvRoot = ModelAdvisor.Root;
            mdladvRoot.publish(rec, char(obj.Group));
        end

    end

    methods(Static)

        function reportResultsSimple(checkObj, model, pass, description, status, recAction)
            arguments
                checkObj
                model
                pass
                description
                status
                recAction
            end

            % ModelAdvisor.ResultDetail's setters require char on older
            % releases; convert at the boundary.
            ElementResults = ModelAdvisor.ResultDetail;
            ElementResults.Description = char(description);
            if verLessThan("MATLAB", "23.2")
                if ~pass
                    ElementResults.IsViolation = true;
                end
            else
                ElementResults.Status = char(status);
                if pass
                    ElementResults.ViolationType = 'pass';
                else
                    ElementResults.ViolationType = 'fail';
                end
            end
            ElementResults.RecAction = char(recAction);
            mdladvObj = Simulink.ModelAdvisor.getModelAdvisor(model); % get object
            mdladvObj.setCheckResultStatus(pass);
            checkObj.setResultDetails(ElementResults);
        end

        function reportFromBlockScan(checkObj, model, scans, description, statusPass, statusFail, recAction)
            arguments
                checkObj
                model (1,1) string
                scans (1,:) struct
                description (1,1) string
                statusPass (1,1) string
                statusFail (1,1) string
                recAction (1,1) string
            end
            % Run a list of "find one BlockType, filter with a
            % predicate" scans and report the accumulated violations
            % through reportResults. Each entry in `scans` must have
            % BlockType (string), Predicate (function_handle taking a
            % block path and returning a logical; true means
            % violation), and FindOpts (cell array of find_system
            % name/value options).
            violatingBlocks = {};
            for ii = 1:numel(scans)
                blocks = find_system(model, scans(ii).FindOpts{:}, ...
                    "BlockType", char(scans(ii).BlockType));
                for jj = 1:numel(blocks)
                    if scans(ii).Predicate(blocks{jj})
                        violatingBlocks{end+1} = blocks{jj}; %#ok<AGROW>
                    end
                end
            end

            if isempty(violatingBlocks)
                vtype = "pass";
            else
                vtype = "fail";
            end
            cigre.advisor.common.CustomCheck.reportResults(checkObj, model, ...
                vtype, violatingBlocks, description, statusPass, statusFail, recAction);
        end

        function reportResults(checkObj, model, vtype, violatingBlocks, description, statusPass, statusFail, recAction)
            arguments
                checkObj
                model
                vtype
                violatingBlocks
                description
                statusPass
                statusFail
                recAction
            end

            mdladvObj = Simulink.ModelAdvisor.getModelAdvisor(model);
            if isempty(violatingBlocks)
                ElementResults = ModelAdvisor.ResultDetail;
                if verLessThan("MATLAB", "23.2")
                    ElementResults.IsViolation = false;
                else
                    ElementResults.ViolationType = 'pass';
                    ElementResults.Status = char(statusPass);
                end
                ElementResults.Description = char(description);

                mdladvObj.setCheckResultStatus(true);
            else
                for idx=1:numel(violatingBlocks)
                    ElementResults(1,idx) = ModelAdvisor.ResultDetail;                  %#ok<AGROW>
                end
                for idx=1:numel(violatingBlocks)

                    if verLessThan("MATLAB", "23.2")
                        ElementResults(idx).setData(violatingBlocks{idx});
                    else
                        ModelAdvisor.ResultDetail.setData(ElementResults(idx), 'SID', violatingBlocks{idx});
                    end

                    ElementResults(idx).Description = char(description);

                    if iscell(statusFail)
                        ElementResults(idx).Status = char(statusFail{idx});
                    else
                        ElementResults(idx).Status = char(statusFail);
                    end

                    if iscell(recAction)
                        ElementResults(idx).RecAction = char(recAction{idx});
                    else
                        ElementResults(idx).RecAction = char(recAction);
                    end

                    if iscell(vtype)
                        thisVtype = char(vtype{idx});
                    else
                        thisVtype = char(vtype);
                    end
                    if verLessThan("MATLAB", "23.2")
                        ElementResults(idx).IsViolation = strcmp(thisVtype, 'fail');
                    else
                        ElementResults(idx).ViolationType = thisVtype;
                    end
                end
                mdladvObj.setCheckResultStatus(false);
            end
            checkObj.setResultDetails(ElementResults);
        end

    end

    methods (Abstract)
        checkCallback(obj, system, checkObj)
    end
end