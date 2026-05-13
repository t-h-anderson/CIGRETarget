classdef Cigre0003InterfaceTypes < cigre.advisor.common.CustomCheck

    % Copyright 2024 The MathWorks, Inc.
    %
    % Requirements
    % ============
    %
    % Check for datatypes not supported by CIGRE such as:
    % Fixed-point, unit64, enums...
    % Warn is boolean type exist as it will be cased.
    %
    % OBS! Boolean types inside busses are not reported
    % OBS! Only first violation in a busobject is reported

    properties (Constant)
        ID = "cigre.interfacetypes.cigre_0003"
        Title = "cigre_0003 Ensure top level interface has CIGRE supported types."
        TitleTips = "Check top level interface for supported types."
        Group = "CIGRE"
        Compile = "PostCompile"
    end

    properties (Constant, Hidden)
        Style = "DetailStyle"
    end

    methods (Static)
        function [ok, b] = isSupportedType(dt)
            dt = string(dt);
            ok = any(ismember(util.TranslateTypes.StandardTypes, dt));
            b = dt == "boolean";
        end

        function [bo, found] = getBusObject(modelVars, dt)
            sourceType = string(modelVars.SourceType);
            dt = string(dt);

            if sourceType == "data dictionary"
                sldd_object = Simulink.data.dictionary.open(modelVars.Source);
                section = getSection(sldd_object, "Design Data");
                entries = find(section, "-value", "-class", "Simulink.Bus");
                sldd_object.close();

                found = false;
                idz = 1;
                while (~found && (idz <= numel(entries)))
                    if string(entries.Name) == dt
                        found = true;
                        bo = entries(idz).getValue;
                    end
                    idz = idz + 1;
                end

                if ~found
                    bo = {};
                end

            elseif sourceType == "base workspace"
                try
                    bo = evalin("base", dt);
                    found = true;
                catch me
                    disp(me);
                    found = false;
                    bo = {};
                end
            else
                error("cigre:advisor:unknownDataSource", ...
                    "Unknown data source type '%s'. Expected 'data dictionary' or 'base workspace'.", ...
                    sourceType);
            end
        end

        function [isok, isbool, mess] = checkBusTypes(modelVars, bo)
            mess = "";
            isbool = false;
            for idx = 1:numel(bo.Elements)
                elementType = string(bo.Elements(idx).DataType);
                if startsWith(elementType, "Bus:")

                    [boNew, found] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.getBusObject(modelVars, extractAfter(elementType, "Bus: "));
                    if found
                        [isok, isbool, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkBusTypes(modelVars, boNew);
                        if ~isok
                            return;
                        end
                    else
                        isok = false;
                        mess = "Did not find: " + extractAfter(elementType, "Bus: ");
                        return;
                    end

                else
                    [isok, isbool] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.isSupportedType(elementType);
                    if ~isok
                        mess = "Unsupported datatype: " + elementType;
                        return;
                    end
                end
            end
            isok = true;
        end

        function [isok, isbus, isbool, found, mess] = checkType(modelVariables, busType, dt)
            if string(busType) == "NOT_BUS"
                [isok, isbool] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.isSupportedType(dt);
                found = true;
                mess = "";
                isbus = false;
            else
                found = false;
                idy = 1;
                isbool = false;
                isbus = true;
                while (~found && (idy <= numel(modelVariables)))
                    if string(dt) == string(modelVariables(idy).Name)
                        found = true;
                        [bo, found_in_source] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.getBusObject(modelVariables(idy), dt);
                        if found_in_source
                            [isok, isbool, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkBusTypes(modelVariables(idy), bo);
                            if ~isok
                                found = true;
                                return;
                            end
                        else
                            isok = false;
                            found = false;
                            mess = "Bus includes non-supported types";
                            return;
                        end
                    end
                    idy = idy + 1;
                end
            end
        end

        function checkCallback(model, checkObj)

            invalidPorts = {};
            statusFail = {};
            violationType = {};

            modelVariables = Simulink.findVars(bdroot, "SearchMethod", "cached");

            inp = find_system(model, "SearchDepth", 1, "BlockType", "Inport");
            for idx = 1:numel(inp)
                ph = get_param(inp{idx}, "PortHandles");
                dt = get_param(ph.Outport, "CompiledPortDataType");
                busType = get_param(ph.Outport, "CompiledBusType");
                [isok, isbus, isbool, found, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkType(modelVariables, busType, dt);

                if ~isok
                    invalidPorts{end+1} = inp{idx};

                    if isbus
                        if ~found
                            statusFail{end+1} = "Could not find busobject: " + string(dt);
                            violationType{end+1} = "fail";
                        else
                            statusFail{end+1} = mess + " in busobject: " + string(dt) + " or sub-bus.";
                            violationType{end+1} = "fail";
                        end
                    else
                        statusFail{end+1} = "Non supported CIGRE type: " + string(dt);
                        violationType{end+1} = "fail";
                    end
                else
                    if isbool
                        invalidPorts{end+1} = inp{idx};
                        statusFail{end+1} = "Boolean type will be cast to uint8_T.";
                        violationType{end+1} = "warn";
                    end
                end

            end

            outp = find_system(model, "SearchDepth", 1, "BlockType", "Outport");
            for idx = 1:numel(outp)
                ph = get_param(outp{idx}, "PortHandles");
                dt = get_param(ph.Inport, "CompiledPortDataType");
                busType = get_param(ph.Inport, "CompiledBusType");
                [isok, isbus, isbool, found, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkType(modelVariables, busType, dt);

                if ~isok
                    invalidPorts{end+1} = outp{idx};
                    if isbus
                        if ~found
                            statusFail{end+1} = "Could not find busobject: " + string(dt);
                            violationType{end+1} = "fail";
                        else
                            statusFail{end+1} = mess + " in busobject: " + string(dt) + " or sub-bus.";
                            violationType{end+1} = "fail";
                        end
                    else
                        statusFail{end+1} = "Non supported CIGRE type: " + string(dt);
                        violationType{end+1} = "fail";
                    end
                else
                    if isbool
                        invalidPorts{end+1} = outp{idx};
                        statusFail{end+1} = "Boolean type will be cast to uint8_T.";
                        violationType{end+1} = "warn";
                    end
                end
            end

            description = "Check that there are no datatypes in the top-level interface that is not supported by CIGRE.";
            statusPass = "No unsupported datatypes found.";
            recAction = "Ensure only CIRGE supported types exist in the top-level interface.";

            cigre.advisor.common.CustomCheck.reportResults(checkObj, model, violationType, invalidPorts, description, statusPass, statusFail, recAction);
        end
    end
end
