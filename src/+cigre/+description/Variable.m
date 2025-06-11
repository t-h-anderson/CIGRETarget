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
                nvp.Dimensions
            end

            objs = cigre.description.Variable.empty(1,0);

            fs = string(fields(nvp));
            fn = numel(fs);

            n = zeros(fn, 1);
            for i = 1:fn
                f = fs(i);
                % Everything is a vector, Dimension is cell array
                % containing potentially disperate vectors
                n(i) = numel(nvp.(f));
            end

            maxN = max(n);

            isOk = all((n == 1) | (n == maxN));
            if ~isOk
                error("Entry must be scalar or all the same lenght");
            end

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

        function objs = fromDataInterface(di, modelName)
            arguments
                di
                modelName (1,1) string = string(nan) % Requried to find default param value
            end

            graphicalNames = cigre.description.Variable.extractGraphicalName(di);
            names = cigre.description.Variable.extractName(di);
            types = cigre.description.Variable.extractType(di);
            baseTypes = cigre.description.Variable.extractBaseType(di);
            mins = cigre.description.Variable.extract(di, "Min");
            maxs = cigre.description.Variable.extract(di, "Max");
            dimensions = cigre.description.Variable.extractDimensions(di);
            defaultValues = cigre.description.Variable.extractDefaultParamValue(di, modelName);

            objs = cigre.description.Variable.create(...
                "GraphicalName", graphicalNames, ...
                "Name", names, ...
                "Type", types, ...
                "BaseType", baseTypes, ...
                "Min", mins, ...
                "Max", maxs, ...
                "Dimensions", dimensions,...
                "DefaultValue", defaultValues ...
                );

        end

    end

    % Methods interacting on coder interface objects
    methods (Static)
        function name = extractGraphicalName(interface)

            name  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                name{i} = string(interface(i).GraphicalName);
            end

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
                imp = interface(i).Implementation;

                if isempty(imp)
                    % Not implemented, so skip
                    continue
                end

                if isa(imp, "coder.descriptor.Variable") || isa(imp, "RTW.Variable")
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

                imp = interface(i).Implementation;

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

            types  = cell(1, numel(interface));

            try
                sz = interface.Size;
            catch
                sz = numel(interface);
            end

            for i = 1:sz
                try
                    types{i} = string(interface(i).Type.BaseType.Name);
                catch
                    types{i} = string(interface(i).Type.Name);
                end
            end

        end

        function value = extractDimensions(interface)
            value = cell(1, numel(interface));
            for i = 1:numel(interface)
                try
                    % TODO: why so many try catches?
                    value{i} = interface(i).Type.Dimensions.toArray();
                catch
                    try
                        value{i} = interface(i).Type.Dimensions;
                    catch
                        value{i} = [1,1];
                    end
                end
            end
        end

        function limitVal = extract(interface, lim)

            type = cigre.description.Variable.extractBaseType(interface);

            limitVal  = cell(1, numel(interface));
            for i = 1:numel(interface)
                limitVal{i} = string(interface(i).Range.(lim));

                if contains(type{i}, "int", "IgnoreCase", true)
                    isInt = true;
                else
                    isInt = false;
                end

                % Assumes we never have e.g. -inf on a max
                if string(limitVal{i}) == "-inf" || string(limitVal{i}) == ""
                    if isInt
                        limitVal{i} = intmin(type{i});
                    else
                        limitVal{i} = realmin;
                    end
                end

                if string(limitVal{i}) == "inf" || string(limitVal{i}) == ""
                    if isInt
                        limitVal{i} = intmax(type{i});
                    else
                        limitVal{i} = realmax / 2; % Using realmax cases a "constant too large error"
                    end
                end
            end

            limitVal = [limitVal{:}]';
        end

        function value = extractDefaultParamValue(interface, modelName)
            arguments
                interface
                modelName (1,1) string = string(nan)
            end

            failedValue = 0; % Nan may be better, but also possibly not supported. 0 is safe.
            if ismissing(modelName)
                value = repelem(failedValue, 1, numel(interface));
            else

                value = cell(1, numel(interface));
                for i = 1:numel(interface)
                    try
                        value{i} = util.findParam(modelName, interface(i).GraphicalName);
                    catch
                        value{i} = failedValue; % Not found
                    end
                end

                value = [value{:}]';
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

