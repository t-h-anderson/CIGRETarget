function modelMetadataTable = getModelMetadata(modelName)
% getModelMetadata Returns a table of every readable parameter on a Simulink model.
%
%   Inputs:
%       modelName - Name of the Simulink model or block to introspect.
%
%   Outputs:
%       modelMetadataTable - Table with one row per (Parameter, Value) pair.
    arguments
        modelName (1,1) string
    end

    if ~bdIsLoaded(modelName)
        try
            load_system(modelName);
        catch ME
            error("getModelMetadata:ModelNotLoaded", ...
                  "The model %s is not loaded and could not be loaded: %s", modelName, ME.message);
        end
    end

    allParams = get_param(modelName, "ObjectParameters");

    paramNames = fieldnames(allParams);
    paramValues = cell(length(paramNames), 1);

    for i = 1:numel(paramNames)
        try
            paramValues{i} = get_param(modelName, paramNames{i});
        catch
            % Some object parameters are write-only or context-dependent
            % and throw on get; record as N/A rather than abort the scan.
            paramValues{i} = "N/A";
        end
    end

    modelMetadataTable = table(paramNames, paramValues, 'VariableNames', {'Parameter', 'Value'});

end
