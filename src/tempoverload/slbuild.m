function slbuild(varargin)

% Remove myself from the path...
here = fileparts(which("slbuild"));
c = onCleanup(@() addpath(here));
rmpath(here);

% If we are CIGRE, do out magic
stf = get_param(varargin{1}, "SystemTargetFile");
if stf == "cigre.tlc"

    % Check if this is from ctrl-B
    args = struct(varargin{3:end});
    isModelBuild = isfield(args, "CalledFromInsideSimulink") ...
        && args.CalledFromInsideSimulink;

    if isModelBuild
        % Build the wrapper and call the utility function
        mdl = get_param(varargin{1}, "Name");
        cigre.internal.buildCigreDLL(mdl);
    else
        % Do the standard build
        slbuild(varargin{:})
    end
else
    % Do the standard build
    slbuild(varargin{:});
end

end