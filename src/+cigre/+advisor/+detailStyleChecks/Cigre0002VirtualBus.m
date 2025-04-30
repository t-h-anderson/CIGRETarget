classdef Cigre0002VirtualBus < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.
    %
    % Requirements
    % ============
    %
    %

    properties (Constant)
        ID = 'cigre.virtualbus.cigre_0002'
        Title = 'cigre_0002 Ensure top level input and output ports have virtual busses connected.'
        TitleTips = 'Check all model inputs and outputs for virtual busses.'
        Group = 'CIGRE'
        Compile = "PostCompile" % ["None", "PostCompile", "PostCompileForCodegen"]
    end

    properties (Constant, Hidden)
        Style = "DetailStyle"
    end
    
    methods (Static)
        function checkCallback(model, checkObj)

            % -------------------------------------------------------------
            %         Check bus creators for invalid test points
            % -------------------------------------------------------------
            invalidPorts = {};
            
            % Check top-level input ports
            inp = find_system(model, 'SearchDepth', 1, 'BlockType', 'Inport');
            for idx=1:numel(inp)
                structout = get_param(inp{idx}, 'BusOutputAsStruct');
                if strcmp(structout, 'on')
                    invalidPorts{end+1} = inp{idx};
                end

            end

            % Check top-level output ports
            outp = find_system(model, 'SearchDepth', 1, 'BlockType', 'Outport');
            for idx=1:numel(outp)
                ph = get_param(outp{idx}, 'PortHandles');
                lh = get_param(ph.Inport, 'Line');
                sph = get_param(lh, 'SrcPortHandle');
                busType = get_param(sph, 'CompiledBusType');
                if strcmp(busType, 'NON_VIRTUAL_BUS')
                    invalidPorts{end+1} = outp{idx};
                end
            end

            % -------------------------------------------------------------
            %                     Process results
            % -------------------------------------------------------------
            description = 'Check that there are no non-virtual busses connected to top level input and output ports.';
            statusPass = 'No non-virtual busses found on top level ports.';
            statusFail = 'The following ports have non-virtual busses connected:';
            recAction = 'Ensure busses connected to top level input and output ports are virtual.';
            if numel(invalidPorts) > 0
                violationType = 'fail';
            else
                violationType = 'pass';
            end
            cigre.advisor.common.CustomCheck.reportResults(checkObj, model, violationType, invalidPorts, description, statusPass, statusFail, recAction);
        end
    end
end