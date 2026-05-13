function buildCodeOnly(modelName)
    arguments
        modelName (1,1) string
    end
    % Build the model generating code only, without invoking the C compiler.
    % The before_make hook still fires, so CIGRE source is generated and
    % can be compiled manually (e.g. in Visual Studio).
    %
    % The slbuild N-V pair 'GenerateCodeOnly' was introduced in a release
    % later than R2020b, which only accepts the model parameter form.
    % Setting GenCodeOnly directly works across every release we care
    % about, so use it unconditionally and restore the original value on
    % exit so the model state is unchanged for any caller that follows.
    modelChar = char(modelName);
    origGenCodeOnly = get_param(modelChar, 'GenCodeOnly');
    cleanup = onCleanup(@() set_param(modelChar, 'GenCodeOnly', origGenCodeOnly)); %#ok<NASGU>
    set_param(modelChar, 'GenCodeOnly', 'on');
    slbuild(modelChar);
end
