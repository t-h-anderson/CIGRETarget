classdef Cigre0002VirtualBus < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.
    %
    % Requirements
    % ============
    %
    %

    properties (Constant)
        ID = "cigre.virtualbus.cigre_0002"
        Title = "cigre_0002 Ensure top level input and output ports have virtual busses connected."
        TitleTips = "Check all model inputs and outputs for virtual busses."
        Group = "CIGRE"
        Compile = "PostCompile"
    end

    properties (Constant, Hidden)
        Style = "DetailStyle"
    end

    methods (Static)
        function checkCallback(model, checkObj)
            arguments
                model (1,1) string
                checkObj
            end

            findOpts = {"SearchDepth", 1};
            scans = struct( ...
                'BlockType', {"Inport", "Outport"}, ...
                'Predicate', {@isNonVirtualBusInport, @isNonVirtualBusOutport}, ...
                'FindOpts',  {findOpts, findOpts});

            cigre.advisor.common.CustomCheck.reportFromBlockScan(checkObj, model, scans, ...
                "Check that there are no non-virtual busses connected to top level input and output ports.", ...
                "No non-virtual busses found on top level ports.", ...
                "The following ports have non-virtual busses connected:", ...
                "Ensure busses connected to top level input and output ports are virtual.");
        end
    end
end

function tf = isNonVirtualBusInport(block)
    tf = string(get_param(block, "BusOutputAsStruct")) == "on";
end

function tf = isNonVirtualBusOutport(block)
    ph = get_param(block, "PortHandles");
    lh = get_param(ph.Inport, "Line");
    sph = get_param(lh, "SrcPortHandle");
    tf = string(get_param(sph, "CompiledBusType")) == "NON_VIRTUAL_BUS";
end