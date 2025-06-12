classdef Variable
    %VARIABLE Summary of this class goes here
    %   Detailed explanation goes here

    properties
        GraphicalName (:,1) string = ""
        Name (:,1) string = ""
        Type (:,1) string = ""
        Pointers (:,1) string = ""
        BaseType (:,1) string = ""
        Dimensions = [NaN, NaN]
        Min (:,1) = NaN
        Max (:,1) = NaN
        DefaultValue (:,1) = NaN

        % Allow, e.g. support for structs of parameters
        NestedVariable (1,:) cigre.description.Variable = cigre.description.Variable.empty(1,0)
    end

    methods
        function obj = Variable(nvp)
            arguments
                nvp.?cigre.description.Variable
            end

            fs = string(fields(nvp));
            for i = 1:numel(fs)
                f = fs(i);
                val = nvp.(f);
                if ~isempty(val)
                    obj.(f) = val;
                end
            end

        end

    end

    methods (Static)

        function objs = create(nvp)
            arguments
                nvp.?cigre.description.Variable
                nvp.NestedVariable
                nvp.Dimensions
            end

            objs = cigre.description.Variable.empty(1,0);

            fs = string(fields(nvp));
            fn = numel(fs);

            % Ensure the data is the correct size
            n = NaN(1,0);
            for i = 1:fn
                f = fs(i);

                % Everything is a vector, Dimension is cell array
                % containing potentially disperate vectors, nested
                % variables can be any size
                switch f
                    case {"NestedVariable", "Dimensions"}
                        continue
                end

                n(end+1) = numel(nvp.(f)); %#ok<AGROW>
            end

            maxN = max(n);

            isOk = all((n == 1) | (n == maxN));
            if ~isOk
                error("Entry must be scalar or all the same lenght");
            end

            % Copy the data into new objects
            for i = 1:maxN
                in = nvp;

                for j = 1:fn
                    f = fs(j);

                    val = nvp.(f);
                    if numel(val) > 1
                        % Everything scalar apart from Dimension which is a
                        % cell array of potentially disperate vectors
                        val = val(i);
                    end

                    if ~isempty(val)
                        if f == "Dimensions"
                            in.(f) = val{:};
                        else
                            in.(f) = val;
                        end
                    end
                end

                incell = namedargs2cell(in);

                objs(i) = cigre.description.Variable(incell{:});

            end

        end

        function objs = fromDataInterface(dis, modelName, nameroot)
            arguments
                dis
                modelName (1,1) string = string(nan) % Required to find default param value
                nameroot (1,:) string = string.empty % Allow nested parameter search
            end

            objs = cigre.description.Variable.empty(1,0);

            for i = 1:numel(dis)
                di = dis(i);

                graphicalNames = cigre.description.Variable.extractGraphicalName(di);
                names = cigre.description.Variable.extractName(di);
                types = cigre.description.Variable.extractType(di);
                baseTypes = cigre.description.Variable.extractBaseType(di);
                mins = cigre.description.Variable.extract(di, "Min");
                maxs = cigre.description.Variable.extract(di, "Max");
                dimensions = cigre.description.Variable.extractDimensions(di);

                paramName = strjoin([nameroot, graphicalNames], ".");
                defaultValues = cigre.description.Variable.extractDefaultParamValue(modelName, paramName);

                if ~isa(di.Type, "coder.descriptor.types.Scalar") ...
                        && (isprop(di.Type, "BaseType") && ~isa(di.Type.BaseType, "coder.descriptor.types.Scalar"))
                    elements = di.Type.BaseType.Elements;

                    sub = cigre.description.Variable.fromDataInterface(elements, modelName, [nameroot, graphicalNames]);
                else
                    sub = cigre.description.Variable.empty(1,0);
                end

                newObjs = cigre.description.Variable(...
                    "GraphicalName", graphicalNames, ...
                    "Name", names, ...
                    "Type", types, ...
                    "BaseType", baseTypes, ...
                    "Min", mins, ...
                    "Max", maxs, ...
                    "Dimensions", dimensions,...
                    "DefaultValue", defaultValues, ...
                    "NestedVariable", sub ...
                    );

                objs = [objs, newObjs];
            end


        end

    end

    % Methods interacting on coder interface objects
    methods (Static)
        function name = extractGraphicalName(interfaces)
            arguments
                interfaces (1,1)
            end

            interface = interfaces;
            if isprop(interface, "GraphicalName")
                name = string(interfaces.GraphicalName);
            else
                name = cigre.description.Variable.extractName(interfaces);
            end

            name = string(name);

        end

        function name = extractName(interface)

            name  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                % Look at the implementation for the name

                if isprop(interface(i), "Implementation")
                    imp = interface(i).Implementation;
                else
                    % E.g. an Aggregate element
                    imp = interface(i);
                end

                if isempty(imp)
                    % Not implemented, so skip
                    continue
                end

                if isa(imp, "coder.descriptor.Variable") ...
                        || isa(imp, "RTW.Variable") ...
                        || isa(imp, "coder.descriptor.types.AggregateElement")
                    name{i} = imp.Identifier;
                elseif isprop(imp, "ElementIdentifier") && ~isempty(imp.ElementIdentifier)
                    name{i} = imp.ElementIdentifier;
                elseif isprop(imp, "Type")
                    % We want the property name
                    type = imp.Type;

                    while(isa(type, "coder.types.Pointer"))
                        % Dricll into pointer
                        type = type.BaseType;
                    end

                    name{i} = type.Name;
                elseif isprop(imp, "Identifier")
                    name{i} = imp.Identifier;
                else
                    error("Extraction of name failed")
                end


            end

        end

        function [types, pointers] = extractType(interface)

            types = cell(1, numel(interface));
            pointers = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz

                if isprop(interface(i), "Implementation")
                    imp = interface(i).Implementation;
                else
                    % E.g. Aggregate element
                    imp = interface(i);
                end

                if isempty(imp) && isprop(interface(i), "Type")
                    % Not implemented, so take the default type
                    type = interface(i).Type;
                elseif isprop(imp, "Type")
                    type = imp.Type;
                else
                    error("Extraction of type failed")
                end

                [type, pointer] = getPointerType(type);

                types{i} = string(type.Identifier);
                pointers{i} = pointer;

            end

        end

        function types = extractBaseType(interface)
            arguments
                interface (1,1)
            end

            if isprop(interface.Type, "BaseType")
                types = string(interface.Type.BaseType.Name);
            else
                types = string(interface.Type.Name);
            end

        end

        function value = extractDimensions(interface)
            arguments
                interface (1,1)
            end

            try
                % TODO: why so many try catches?
                value = interface.Type.Dimensions.toArray();
            catch
                try
                    value = interface.Type.Dimensions;
                catch
                    value = [1,1];
                end
            end
        end

        function limitVal = extract(interface, lim)
            arguments
                interface (1,1)
                lim (1,1) string {mustBeMember(lim, ["Min", "Max"])}
            end

            type = cigre.description.Variable.extractBaseType(interface);

            if ~isprop(interface, "Range")
                % E.g. aggregate element
                limitVal = "";
            else
                limitVal = string(interface.Range.(lim));
            end

            if contains(type, "int", "IgnoreCase", true)
                isInt = true;
            else
                isInt = false;
            end

            % Assumes we never have e.g. -inf on a max
            if string(limitVal) == "-inf" || (string(limitVal) == "" && lim == "Min")
                if isInt
                    limitVal = intmin(type);
                else
                    limitVal = realmin;
                end
            end

            if string(limitVal) == "inf" || (string(limitVal) == "" && lim == "Max")
                if isInt
                    limitVal = intmax(type);
                else
                    limitVal = realmax / 2; % Using realmax cases a "constant too large error"
                end
            end

        end

        function value = extractDefaultParamValue(modelName, paramName)
            arguments
                modelName (1,1) string = string(nan)
                paramName (1,1) string = string(nan)
            end

            failedValue = 0; % Nan may be better, but also possibly not supported. 0 is safe.
            if ismissing(modelName) || ismissing(paramName)
                value = failedValue;
            else

                try
                    value = util.findParam(modelName, paramName);
                catch
                    value = failedValue; % Not found
                end

            end

        end

    end

end

function [type, pointers] = getPointerType(type)

pointers = "";
if meta.class.fromName(class(type)) <= ?coder.types.Pointer || ...
        meta.class.fromName(class(type)) <= ?coder.descriptor.types.Pointer || ...
        meta.class.fromName(class(type)) <= ?coder.descriptor.types.Matrix
    type = type.BaseType;
    [type, pointers] = getPointerType(type);
    pointers = pointers + "*";
end

end

