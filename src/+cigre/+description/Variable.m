classdef Variable
    %VARIABLE Summary of this class goes here
    %   Detailed explanation goes here

    properties
        SimulinkName (:,1) string = ""
        ExternalName (:,1) string = ""
        Type (:,1) string = ""
        Pointers (:,1) string = ""
        BaseType (:,1) string = ""
        Dimensions = [NaN, NaN]
        Min (:,1) = NaN
        Max (:,1) = NaN
        DefaultValue (:,1) = NaN

        StorageSpecifier (1,1) string = ""
        GetMethod (1,1) string = ""

        % Allow, e.g. support for structs of parameters
        NestedVariable (1,:) cigre.description.Variable = cigre.description.Variable.empty(1,0)
    end

    properties (Dependent)
        IsLeaf
        IsModelArgument (1,1) logical
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

        function val = get.IsLeaf(obj)
            val = isempty(obj.NestedVariable);
        end
        
        function val = get.IsModelArgument(obj)
            val = contains(obj.StorageSpecifier, "ModelArgument");
        end

        function leaves = getLeaves(objs)

            idx = [objs.IsLeaf];
            leaves = objs(idx);

            if any(~idx)
                notLeaves = objs(~idx);
                next = [notLeaves.NestedVariable];
                leaves = [leaves, next.getLeaves];
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

        % Output of external names allows us to easily keep track of what
        % external names have been used in nested structs
        function [objs, usedExternalNames] = fromDataInterface(dis, modelName, nameroot, nvp)
            arguments
                dis
                modelName (1,1) string = string(nan) % Required to find default param value
                nameroot (1,:) string = string.empty % Allow nested parameter search
                nvp.OverloadStorage (1,1) string = string(nan)
                nvp.UsedExternalNames (1,:) string = string.empty(1,0)
            end

            objs = cigre.description.Variable.empty(1,0);

            usedExternalNames = nvp.UsedExternalNames;
            for i = 1:numel(dis)

                di = dis(i);

                simulinkName = cigre.description.Variable.extractSimulinkName(di);
                externalName = cigre.description.Variable.extractExternalName(di, "NameRoot", nameroot);
                type = cigre.description.Variable.extractType(di);
                baseType = cigre.description.Variable.extractBaseType(di);
                minVal = cigre.description.Variable.extract(di, "Min");
                maxVal = cigre.description.Variable.extract(di, "Max");
                dimensions = cigre.description.Variable.extractDimensions(di);
                [storage, getMethod] = cigre.description.Variable.extractStorageSpecifier(di);
                if ~ismissing(nvp.OverloadStorage)
                    storage = nvp.OverloadStorage;
                end                    

                paramName = strjoin([nameroot, simulinkName], ".");
                defaultValues = cigre.description.Variable.extractDefaultParamValue(modelName, paramName);

                % Determine if the data interface describes a parameter
                % struct
                subExternalNames = string.empty(1,0);
                if ~isa(di.Type, "coder.descriptor.types.Scalar")

                    if isprop(di.Type, "BaseType")
                        typeObj = di.Type.BaseType;
                    else
                        typeObj = di.Type;
                    end
                    
                    % Structs have elements, so recursively traverse the
                    % struct
                    if isprop(typeObj, "Elements")
                        elements = typeObj.Elements;
                        % Pass the storage onto the children in the case of
                        % a struct
                        [sub, subExternalNames] = cigre.description.Variable.fromDataInterface(elements, modelName, [nameroot, simulinkName], ...
                            "OverloadStorage", storage, ...
                            "UsedExternalNames", usedExternalNames);
                    else
                        sub = cigre.description.Variable.empty(1,0);
                    end

                else
                    sub = cigre.description.Variable.empty(1,0);
                end
                
                % Adapt the names to allow indexing into structs and to
                % avoid duplicate names
                if ~isempty(nameroot)
                    % Nested parameter
                    simulinkName = paramName;
                end

                usedExternalNames = [usedExternalNames, subExternalNames];
                externalName = matlab.lang.makeUniqueStrings(externalName, usedExternalNames);
                usedExternalNames = [usedExternalNames, externalName];

                newObjs = cigre.description.Variable(...
                    "SimulinkName", simulinkName, ...
                    "ExternalName", externalName, ...
                    "Type", type, ...
                    "BaseType", baseType, ...
                    "Min", minVal, ...
                    "Max", maxVal, ...
                    "Dimensions", dimensions,...
                    "DefaultValue", defaultValues, ...
                    "StorageSpecifier", storage, ...
                    "GetMethod", getMethod, ...
                    "NestedVariable", sub ...
                    );

                objs = [objs, newObjs];
            end

            % Ensure external names are unique
            ext = [objs.ExternalName];
            ext = matlab.lang.makeUniqueStrings(ext);
            ext = num2cell(ext);
            [objs.ExternalName] = deal(ext{:});


        end

    end

    % Methods interacting on coder interface objects
    methods (Static)
        function name = extractSimulinkName(interface)
            arguments
                interface (1,1)
            end

            if isprop(interface, "SimulinkName")
                name = string(interface.GraphicalName);
            else
                name = cigre.description.Variable.extractExternalName(interface);
            end

            name = string(name);

        end

        function name = extractExternalName(interface, nvp)
            arguments
                interface (1,1)
                nvp.NameRoot (1,:) string = string.empty(1,0)
            end

            % Look at the implementation for the name

            if isprop(interface, "Implementation")
                imp = interface.Implementation;
            else
                % E.g. an Aggregate element
                imp = interface;
            end

            if isa(imp, "coder.descriptor.Variable") ...
                    || isa(imp, "RTW.Variable") ...
                    || isa(imp, "coder.descriptor.types.AggregateElement")
                name = imp.Identifier;
            elseif isa(imp, "coder.descriptor.CustomExpression")
                % We are a get/set parameter
                % TODO: The get function can be customised. Can we make this more
                % robust?
                name = erase(imp.ReadExpression, "get_");
            elseif isprop(imp, "ElementIdentifier") && ~isempty(imp.ElementIdentifier)
                name = imp.ElementIdentifier;
            elseif isprop(imp, "Type")
                % We want the property name
                type = imp.Type;

                while(isa(type, "coder.types.Pointer"))
                    % Dricll into pointer
                    type = type.BaseType;
                end

                if isprop(type, "ExternalName")
                    name = type.name;
                else
                    name = type.Name;
                end
            elseif isprop(imp, "Identifier")
                name = imp.Identifier;
            else
                error("Extraction of name failed")
            end

            name = string(name);

            name = strjoin([nvp.NameRoot, name], "_");

        end

        function [type, pointer] = extractType(interface)
            arguments
                interface (1,1)
            end

            if isprop(interface, "Implementation")
                imp = interface.Implementation;
            else
                % E.g. Aggregate element
                imp = interface;
            end

            if isempty(imp) && isprop(interface, "Type")
                % Not implemented, so take the default type
                type = interface.Type;
            elseif isprop(imp, "Type")
                type = imp.Type;
            else
                error("Extraction of type failed")
            end

            [type, pointer] = getPointerType(type);

            if isprop(type, "Identifier")
                type = string(type.Identifier);
            else
                type = "";
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

        function [storage, getMethod] = extractStorageSpecifier(interface)
        
            getMethod = "";
            if isa(interface, "coder.descriptor.types.AggregateElement")
                storage = "InternalStruct";
                return
            end

            imp = interface.Implementation;

            if isprop(imp, "StorageSpecifier")
                storage = imp.StorageSpecifier;
            elseif isprop(imp, "ReadExpression")
                storage = "GetSet";
                getMethod = imp.ReadExpression;
            elseif isprop(imp, "BaseRegion")
                storage = "ModelArgument:" + imp.BaseRegion.Identifier;
            else
                storage = "unknown";
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
                    [~, value] = util.findParam(modelName, paramName);
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

