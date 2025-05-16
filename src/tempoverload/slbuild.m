function slbuild(modelName, varargin)
% SLBUILD builds a Simulink model based on the specified parameters.
% Usage: slbuild(modelName, varargin)
% modelName: Name of the Simulink model to build.
% varargin: Additional parameters for the build process.

% Remove myself from the path...
here = fileparts(which("slbuild"));
c = onCleanup(@() addpath(here));
rmpath(here);

% Try to get the SystemTargetFile
try
    stf = get_param(modelName, "SystemTargetFile");
catch ME
    error('Failed to retrieve SystemTargetFile: %s', ME.message);
end

% If we are CIGRE, do our magic
if stf == "cigre.tlc"

    % Check if this is from ctrl-B
    args = struct(varargin{2:end});
    isModelBuild = isfield(args, "CalledFromInsideSimulink") ...
        && args.CalledFromInsideSimulink;

    if isModelBuild
        % Build the wrapper and call the utility function
        mdl = get_param(modelName, "Name");
        cigre.internal.build(mdl);
    else
        % Do the standard build
        slbuild(modelName, varargin{:})
    end
else
    % Do the standard build
    slbuild(modelName, varargin{:});
end

end