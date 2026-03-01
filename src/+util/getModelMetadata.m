function modelMetadataTable = getModelMetadata(modelName)
    % getModelMetadata Retrieves all metadata for a Simulink model and displays in a table.
    %
    %   modelMetadataTable = getModelMetadata(modelName) returns a table containing
    %   the metadata of the model specified by modelName.
    %
    %   Inputs:
    %       modelName - Name of the Simulink model or block to get metadata from.
    %
    %   Outputs:
    %       modelMetadataTable - Table containing the metadata of the model.
    arguments
        modelName (1,1) string
    end

    % Check if the model is loaded, if not try to load it
    if ~bdIsLoaded(modelName)
        try
            load_system(modelName);
        catch ME
            error("getModelMetadata:ModelNotLoaded", ...
                  "The model %s is not loaded and could not be loaded: %s", modelName, ME.message);
        end
    end
    
    % Get all the parameters of the model
    allParams = get_param(modelName, "ObjectParameters");
    
    % Retrieve the names and values of the parameters
    paramNames = fieldnames(allParams);
    paramValues = cell(length(paramNames), 1);
    
    for i = 1:numel(paramNames)
        try
            paramValues{i} = get_param(modelName, paramNames{i});
        catch
            % Some parameters might not be readable, so we catch the error and continue
            paramValues{i} = "N/A";
        end
    end
    
    % Create a table with the parameter names and values
    modelMetadataTable = table(paramNames, paramValues, 'VariableNames', ["Parameter", "Value"]);

end