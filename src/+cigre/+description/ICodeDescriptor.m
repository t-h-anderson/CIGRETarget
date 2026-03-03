classdef ICodeDescriptor < handle
    % Abstract interface for all Simulink/coder/file I/O

    properties (Constant)
        % Reserved CIGRE DLL interface identifiers. Variables whose external
        % name clashes with these are renamed with a suffix to prevent C struct
        % field name conflicts.
        ReservedCigreIdentifiers (1,:) string = ["inputs", "outputs"]
    end

    methods (Abstract)
        % Return a ModelMetadata object populated from the Simulink model.
        metadata = getModelMetadata(obj)

        % Return the generated wrapper header (.h) as a string column vector of lines.
        code = getWrapperHeaderCode(obj)

        % Return the generated wrapper source (.c) as a string column vector of lines.
        code = getWrapperSourceCode(obj)

        % Return a Variable array for the wrapper model inport signals.
        vars = getInports(obj)

        % Return a Variable array for the wrapper model outport signals.
        vars = getOutports(obj)

        % Return a Variable array for the referenced model parameters.
        vars = getParameters(obj)

        % Extract and partition InternalData from the RTW codeInfo into three
        % Variable arrays: [internalVars, inputVars, outputVars].
        % The RTM struct variable is included in internalVars.
        [internalVars, inputVars, outputVars] = getCodeInfoVariables(obj)

        % Return the FunctionInterface for the wrapper Initialize function.
        iface = getInitializeInterface(obj)

        % Return the FunctionInterface for the wrapper Output (step) function.
        iface = getOutputInterface(obj)

        % Return the FunctionInterface for the referenced model Terminate function.
        iface = getTerminateInterface(obj)

        % Return the FunctionInterface for the model reference Initialize function,
        % used to support snapshot restart.
        iface = getModelRefInitializeInterface(obj)
    end
end