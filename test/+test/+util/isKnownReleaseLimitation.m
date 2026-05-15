function tf = isKnownReleaseLimitation(me)
% isKnownReleaseLimitation True for codegen failures that are a known
% release-specific shortcoming rather than a real regression.
%
% Some MATLAB releases fail codegen for a test model in ways the suite
% cannot work around without re-implementing per-release support in
% production code. Callers treat a match as assumeFail rather than
% failure, so the test reports Incomplete in the CI summary instead of
% red, while the underlying problem stays tracked by its own issue.
%
% Current entries:
%
%   Simulink:modelReference:ParamIntf_UngroupedArgument
%     R2020b. Triggered when a model uses Model-block argument
%     parameters whose storage class isn't set to a per-instance
%     class. R2021a+ handles this via coder.mapping.utils.create +
%     setDataDefault("MultiInstance") in createBusExplodedWrapper;
%     R2020b lacks the "MultiInstance" storage value and the try/catch
%     around that call silently skips it, leaving the parameter at
%     "Auto" which tlc_c rejects.
%
%   Simulink:modelReference:ErrorGraphicalInterfaceInconsistency
%     R2026a. Building the CIGRE wrapper around Test_CP fails the
%     referenced-model interface check ("Computed interface
%     information must match saved interface information for
%     referenced model Test_CP"). Test_CP is a model-reference
%     arguments model; its saved interface is inconsistent with what
%     R2026a computes. Tracked separately; properly resolved by the
%     test-model rework in issue #48.
arguments
    me MException
end

knownIds = [
    "Simulink:modelReference:ParamIntf_UngroupedArgument"
    "Simulink:modelReference:ErrorGraphicalInterfaceInconsistency"
];
tf = any(string(me.identifier) == knownIds);
end
