classdef FakeRangedInterface
    % Minimal stand-in for a Simulink coder data interface.
    %
    % Used by tVariable to exercise cigre.description.Variable.extract and
    % extractBaseType without a live Simulink session. Only the Type and
    % Range properties those methods read are modelled; assign Type a
    % struct with a Name field and Range a struct with Min / Max fields.
    properties
        Type
        Range
    end
end
