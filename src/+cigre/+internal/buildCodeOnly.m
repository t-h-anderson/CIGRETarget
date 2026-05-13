function buildCodeOnly(modelName)
    arguments
        modelName (1,1) string
    end
    % Build the model generating code only, without invoking the C compiler.
    % The before_make hook still fires, so CIGRE source is generated and
    % can be compiled manually (e.g. in Visual Studio).
    %
    % The N-V pair name has to be a char vector: R2020b's slbuild
    % rejects strings for the name slot with ParamMustBeChar.
    slbuild(modelName, 'generateCodeOnly', true);
end
