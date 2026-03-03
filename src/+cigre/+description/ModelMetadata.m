classdef ModelMetadata
    % Simulink model properties read via get_param.

    properties
        SystemTargetFile (1,1) string = ""
        ModelVersion (1,1) string = "Unknown"
        Description (1,1) string = ""
        SampleTime (1,1) string = ""
        CreatedBy (1,1) string = ""
        CreatedOn (1,1) string = ""
        ModifiedBy (1,1) string = "Unknown"
        ModifiedOn (1,1) string = ""
        ModelModifiedComment (1,1) string = ""
        ModelModifiedHistory (1,1) string = ""
    end

    methods
        function obj = ModelMetadata(nvp)
            arguments
                nvp.SystemTargetFile (1,1) string = ""
                nvp.ModelVersion (1,1) string = "Unknown"
                nvp.Description (1,1) string = ""
                nvp.SampleTime (1,1) string = ""
                nvp.CreatedBy (1,1) string = ""
                nvp.CreatedOn (1,1) string = ""
                nvp.ModifiedBy (1,1) string = "Unknown"
                nvp.ModifiedOn (1,1) string = ""
                nvp.ModelModifiedComment (1,1) string = ""
                nvp.ModelModifiedHistory (1,1) string = ""
            end
            obj.SystemTargetFile = nvp.SystemTargetFile;
            obj.ModelVersion = nvp.ModelVersion;
            obj.Description = nvp.Description;
            obj.SampleTime = nvp.SampleTime;
            obj.CreatedBy = nvp.CreatedBy;
            obj.CreatedOn = nvp.CreatedOn;
            obj.ModifiedBy = nvp.ModifiedBy;
            obj.ModifiedOn = nvp.ModifiedOn;
            obj.ModelModifiedComment = nvp.ModelModifiedComment;
            obj.ModelModifiedHistory = nvp.ModelModifiedHistory;
        end
    end
end