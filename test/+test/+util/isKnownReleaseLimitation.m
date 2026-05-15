function tf = isKnownReleaseLimitation(me)
% isKnownReleaseLimitation True for codegen failures that are a documented
% older-release shortcoming rather than a real regression.
%
% A documented limitation the test cannot work around without
% re-implementing per-release support in production code. Callers treat
% a match as assumeFail rather than failure, so the test reports
% Incomplete in the CI summary instead of red.
%
% Current entries:
%
%   Simulink:modelReference:ParamIntf_UngroupedArgument
%     Triggered when a model uses Model-block argument parameters whose
%     storage class isn't set to a per-instance class. R2021a+ handles
%     this via coder.mapping.utils.create + setDataDefault("MultiInstance")
%     in createBusExplodedWrapper; R2020b lacks the "MultiInstance"
%     storage value and the try/catch around that call silently skips it,
%     leaving the parameter at "Auto" which tlc_c rejects.
arguments
    me MException
end

knownIds = [
    "Simulink:modelReference:ParamIntf_UngroupedArgument"
];
tf = any(string(me.identifier) == knownIds);
end
