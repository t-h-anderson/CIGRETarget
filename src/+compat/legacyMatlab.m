function tf = legacyMatlab(version)
% legacyMatlab Release-gate seam for the src/For2020a/ shims.
%
%   tf = compat.legacyMatlab()        % verLessThan("MATLAB", "9.9")
%   tf = compat.legacyMatlab("9.12")  % verLessThan("MATLAB", "9.12")
%
% Tests force the legacy branch on any release by passing
% LegacyMatlab=true to the shim (the NV-pair default is this
% function), so the older code in src/For2020a/ is exercised on the
% CI matrix even though it never naturally triggers there.
arguments
    version (1,1) string = "9.9"
end
tf = verLessThan("MATLAB", char(version));
end
