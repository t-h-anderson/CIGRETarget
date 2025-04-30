function rtwTargetInfo(tr)
%RTWTARGETINFO Registration file for custom toolchains.

% Copyright 2012-2017 The MathWorks, Inc.

tr.registerTargetInfo(@createToolchainInfoRegs);

end