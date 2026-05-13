function slbuild(modelName, varargin)
arguments
    modelName (1,1) string
end
arguments (Repeating)
    varargin
end
% SLBUILD builds a Simulink model based on the specified parameters.
% Usage: slbuild(modelName, varargin)
%   modelName - Name of the Simulink model to build.
%   varargin  - Forwarded to the built-in slbuild.

% Drop this overload off the path before recursing so the underlying
% built-in slbuild is selected; the onCleanup restores it afterwards.
here = fileparts(which("slbuild"));
c = onCleanup(@() addpath(here));
rmpath(here);

try
    stf = get_param(modelName, "SystemTargetFile");
catch ME
    error("Failed to retrieve SystemTargetFile: %s", ME.message);
end

if stf == "cigre.tlc"

    % Detect Simulink's internal Ctrl-B build path; in that case build the
    % wrapper via cigre.internal.build instead of the standard slbuild.
    args = struct(varargin{2:end});
    isModelBuild = isfield(args, "CalledFromInsideSimulink") ...
        && args.CalledFromInsideSimulink;

    if isModelBuild
        mdl = get_param(modelName, "Name");
        cigre.internal.build(mdl);
    else
        slbuild(modelName, varargin{:})
    end
else
    slbuild(modelName, varargin{:});
end

end
