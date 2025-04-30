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
    %
    %-------------------------------------------------------------

    properties (Constant)
        ID = 'cigre.interfacetypes.cigre_0003'
        Title = 'cigre_0003 Ensure top level interface has CIGRE supported types.'
        TitleTips = 'Check top level interface for supported types.'
        Group = 'CIGRE'
        Compile = "PostCompile" % ["None", "PostCompile", "PostCompileForCodegen"]
    end

    properties (Constant, Hidden)
        Style = "DetailStyle"
    end

    methods (Static)
        function [ok, b] = isSupportedType(dt)
            if sum(ismember(util.TranslateTypes.StandardTypes, dt)) > 0.5  % Better way?
                ok = true;
            else
                ok = false;
            end
            b = strcmp(dt, 'boolean');
        end

        function [bo, found] = getBusObject(modelVars, dt)
           
            if strcmp(modelVars.SourceType, 'data dictionary')
                sldd_object = Simulink.data.dictionary.open(modelVars.Source);
                section = getSection(sldd_object, 'Design Data');
                entries = find(section, '-value', '-class', 'Simulink.Bus');
                sldd_object.close();

                % Find dt object
                found = false;
                idz = 1;
                while (~found && (idz <= numel(entries)))
                    if strcmp(entries.Name, dt)
                        found = true;
                        bo = entries(idz).getValue;
                    end
                    idz = idz + 1;
                end

                if ~found
                    bo = {};
                end

            elseif strcmp(modelVars.SourceType, 'base workspace')
                try
                    bo = evalin("base", dt);
                    found = true;
                catch me
                    disp(me);
                    found = false;
                    bo = {};
                end               
            else
                error('***** Unknown data source *****');
            end
        end

        function [isok, isbool, mess] = checkBusTypes(modelVars, bo)
            mess = '';
            isbool = false;
            for idx=1:numel(bo.Elements)
                if strcmp(bo.Elements(idx).DataType(1:4), 'Bus:')

                    [boNew, found] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.getBusObject(modelVars, bo.Elements(idx).DataType(6:end));
                    if found
                        [isok, isbool, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkBusTypes(modelVars, boNew);
                        if ~isok
                            return;
                        end
                    else
                        isok = false;
                        mess = ['Did not find: ', bo.Elements(idx).DataType(6:end)];
                        return;
                    end

                else
                    [isok, isbool] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.isSupportedType(bo.Elements(idx).DataType);
                    if ~isok
                        mess = ['Unsupported datatype: ', bo.Elements(idx).DataType];
                        return;
                    end
                end
            end
            isok = true;
        end

        function [isok, isbus, isbool, found, mess] = checkType(modelVariables, busType, dt)
            if strcmp(busType, 'NOT_BUS')

                % We have a non-bus type
                [isok, isbool] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.isSupportedType(dt);
                found = true;
                mess = '';
                isbus = false;
            else
                % We have a bus type
                found = false;
                idy = 1;
                isbool = false;
                isbus = true;
                while (~found && (idy <= numel(modelVariables)))
                    if strcmp(dt, modelVariables(idy).Name)
                        found = true;
                        [bo, found_in_source] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.getBusObject(modelVariables(idy), dt);
                        if found_in_source
                            [isok, isbool, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkBusTypes(modelVariables(idy), bo);
                            if ~isok                                 
                                %mess = 'Bus includes non-supported types';
                                found = true;
                                return;
                            end
                        else
                            % Report error not found                       
                            isok = false;
                            found = false;
                            mess = 'Bus includes non-supported types';
                            return;
                        end
                    end
                    idy = idy + 1;
                end
            end
        end
 
        function checkCallback(model, checkObj)

            % -------------------------------------------------------------
            %         Check bus creators for invalid test points
            % -------------------------------------------------------------
            invalidPorts = {};
            statusFail = {};
            violationType = {};
            
            modelVariables = Simulink.findVars(bdroot,'SearchMethod','cached');

            % Check top-level input ports
            inp = find_system(model, 'SearchDepth', 1, 'BlockType', 'Inport');
            for idx=1:numel(inp)
                ph = get_param(inp{idx}, 'PortHandles');
                dt = get_param(ph.Outport, 'CompiledPortDataType');
                busType = get_param(ph.Outport, 'CompiledBusType');       
                [isok, isbus, isbool, found, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkType(modelVariables, busType, dt);  

                % [~, portName] = fileparts(inp{idx});
                % disp([portName, ': isok(', num2str(isok), ') isbus(', num2str(isbus), ...
                %     ') isbool(', num2str(isbool), ') found(', num2str(found), ...
                %     ') mess: ', mess, ' DataType [', dt, ']']);

                if ~isok
                    invalidPorts{end+1} = inp{idx};

                    if isbus
                        if ~found
                            statusFail{end+1} = ['Could not find busobject: ', dt];
                            violationType{end+1} = 'fail';
                        else
                            statusFail{end+1} = [mess, ' in busobject: ', dt, ' or sub-bus.'];
                            violationType{end+1} = 'fail';
                        end
                    else
                        statusFail{end+1} = ['Non supported CIGRE type: ', dt];
                        violationType{end+1} = 'fail';
                    end
                else
                    if isbool
                        invalidPorts{end+1} = inp{idx};
                        statusFail{end+1} = 'Boolean type will be cast to uint8_T.';
                        violationType{end+1} = 'warn';
                    end
                end

            end

            % Check top-level output ports
            outp = find_system(model, 'SearchDepth', 1, 'BlockType', 'Outport');
            for idx=1:numel(outp)
                ph = get_param(outp{idx}, 'PortHandles');
                dt = get_param(ph.Inport, 'CompiledPortDataType');
                busType = get_param(ph.Inport, 'CompiledBusType');
                [isok, isbus, isbool, found, mess] = cigre.advisor.detailStyleChecks.Cigre0003InterfaceTypes.checkType(modelVariables, busType, dt);
                
                % [~, portName] = fileparts(outp{idx});
                % disp([portName, ': isok(', num2str(isok), ') isbus(', num2str(isbus), ...
                %     ') isbool(', num2str(isbool), ') found(', num2str(found), ...
                %     ') mess: ', mess, ' DataType [', dt, ']']);

                if ~isok
                    invalidPorts{end+1} = outp{idx};
                    if isbus
                        if ~found
                            statusFail{end+1} = ['Could not find busobject: ', dt];
                            violationType{end+1} = 'fail';
                        else
                            statusFail{end+1} = [mess, ' in busobject: ', dt, ' or sub-bus.'];
                            violationType{end+1} = 'fail'; 
                        end
                    else
                        statusFail{end+1} = ['Non supported CIGRE type: ', dt];
                        violationType{end+1} = 'fail';
                    end
                else              
                    if isbool
                        invalidPorts{end+1} = outp{idx};
                        statusFail{end+1} = 'Boolean type will be cast to uint8_T.';
                        violationType{end+1} = 'warn';
                    end
                end
            end

            % -------------------------------------------------------------
            %                     Process results
            % -------------------------------------------------------------
            description = 'Check that there are no datatypes in the top-level interface that is not supported by CIGRE.';
            statusPass = 'No unsupported datatypes found.';
            recAction = 'Ensure only CIRGE supported types exist in the top-level interface.';

            %statusFail = 'The following ports have unsupported datatypes:';
            cigre.advisor.common.CustomCheck.reportResults(checkObj, model, violationType, invalidPorts, description, statusPass, statusFail, recAction);
        end
    end
end