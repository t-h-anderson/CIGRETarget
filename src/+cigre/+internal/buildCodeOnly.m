function buildCodeOnly(modelName)
    arguments
        modelName (1,1) string
    end
    % Build the model generating code only, without invoking the C compiler.
    % The before_make hook still fires, so CIGRE source is generated and
    % can be compiled manually (e.g. in Visual Studio).
    slbuild(modelName, "GenerateCodeOnly", true);
end
