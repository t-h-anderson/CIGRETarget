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
        Style (1,:) char %{mustBeMember(Style, ["StyleOne", "StyleTwo", "StyleThree", "DetailStyle"])}
    end


    methods
        function obj = CustomCheck()

            % Create ModelAdvisor.Check object and set properties.
            rec = ModelAdvisor.Check(obj.ID);
            rec.Title = obj.Title;
            rec.TitleTips = obj.TitleTips;
            rec.CallbackContext = obj.Compile;
            rec.setCallbackFcn(@(system, checkObj) obj.checkCallback(system, checkObj), obj.Compile, obj.Style);
            rec.CallbackStyle = obj.Style;

            mdladvRoot = ModelAdvisor.Root;
            mdladvRoot.publish(rec, obj.Group); % publish check into Group.
        end

    end

    methods(Static)

        function reportResultsSimple(checkObj, model, pass, description, status, recAction)
            
            % Check args
            
            ElementResults = ModelAdvisor.ResultDetail;
            ElementResults.Description = description;            
            if verLessThan("MATLAB", "23.2")
                if pass
                    
                else
                    ElementResults.IsViolation = true;
                end   
            else
                ElementResults.Status = status;
                if pass
                    ElementResults.ViolationType = 'pass';
                else
                    ElementResults.ViolationType = 'fail';
                end
            end
            ElementResults.RecAction = recAction;
            mdladvObj = Simulink.ModelAdvisor.getModelAdvisor(model); % get object
            mdladvObj.setCheckResultStatus(pass);
            checkObj.setResultDetails(ElementResults);
        end

        function reportResults(checkObj, model, vtype, violatingBlocks, description, statusPass, statusFail, recAction)
            
            % Check args

            mdladvObj = Simulink.ModelAdvisor.getModelAdvisor(model); % get object
            if isempty(violatingBlocks)
                ElementResults = ModelAdvisor.ResultDetail;
                if verLessThan("MATLAB", "23.2")
                    ElementResults.IsViolation = false;
                else
                    ElementResults.ViolationType = 'pass';
                    ElementResults.Status = statusPass;
                end
                ElementResults.Description = description;
                
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
                   
                    ElementResults(idx).Description = description;
                    
                    if iscell(statusFail)
                        ElementResults(idx).Status = statusFail{idx};
                    else
                        ElementResults(idx).Status = statusFail;
                    end

                    if iscell(recAction)
                        ElementResults(idx).RecAction =  recAction{idx};
                    else
                        ElementResults(idx).RecAction =  recAction;
                    end
                    
                    if iscell(vtype)
                        if verLessThan("MATLAB", "23.2")
                            if strcmp(vtype{idx}, 'fail')
                                ElementResults(idx).IsViolation = true;
                            else
                                ElementResults(idx).IsViolation = false;
                            end        
                        else
                            ElementResults(idx).ViolationType = vtype{idx};
                        end
                    else
                        if verLessThan("MATLAB", "23.2")
                            if strcmp(vtype, 'fail')
                                ElementResults(idx).IsViolation = true;
                            else
                                ElementResults(idx).IsViolation = false;
                            end
                        else
                            ElementResults(idx).ViolationType = vtype;
                        end
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