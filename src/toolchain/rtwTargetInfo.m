function rtwTargetInfo(tr)
%RTWTARGETINFO Registration file for custom toolchains.

% Copyright 2012-2017 The MathWorks, Inc.

arguments
    tr (1,1)
end

tr.registerTargetInfo(@createToolchainInfoRegs);

end