classdef FunctionInterface
    % Object representing a C function prototype extracted from the
    % Simulink code descriptor. Returned by CodeDescriptor methods so that
    % ModelDescription has no direct dependency on coder.descriptor types.
    %
    % An empty interface (Name == "") signals that no function was found,
    % avoiding the need for callers to handle [] vs object.

    properties
        Name (1,1) string = ""
        ArgumentNames (1,:) string = string.empty(1,0)
        ArgumentTypes (1,:) string = string.empty(1,0)
        ArgumentPointers (1,:) string = string.empty(1,0)
    end

    properties (Dependent)
        IsEmpty (1,1) logical
    end

    methods
        function obj = FunctionInterface(nvp)
            arguments
                nvp.Name (1,1) string = ""
                nvp.ArgumentNames (1,:) string = string.empty(1,0)
                nvp.ArgumentTypes (1,:) string = string.empty(1,0)
                nvp.ArgumentPointers (1,:) string = string.empty(1,0)
            end
            obj.Name = nvp.Name;
            obj.ArgumentNames = nvp.ArgumentNames;
            obj.ArgumentTypes = nvp.ArgumentTypes;
            obj.ArgumentPointers = nvp.ArgumentPointers;
        end

        function val = get.IsEmpty(obj)
            val = obj.Name == "";
        end
    end
end