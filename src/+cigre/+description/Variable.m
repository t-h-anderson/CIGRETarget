classdef Variable
    properties
        SimulinkName (:,1) string = ""  % Graphical name in Simulink
        CIGREName (:,1) string = ""     % Name exposed in CIGRE DLL
        ERTName (:,1) string = ""       % Internal name within generated ERT code

        Type (:,1) string = ""
        Pointers (:,1) string = ""
        BaseType (:,1) string = ""
        Dimensions = [NaN, NaN]
        Min (:,1) = NaN
        Max (:,1) = NaN
        DefaultValue = NaN

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

            % CIGREName defaults to a C-safe version of SimulinkName.
            % ERTName defaults to CIGREName (usually the same C identifier).
            if all(obj.CIGREName == "")
                obj.CIGREName = matlab.lang.makeValidName(obj.SimulinkName);
            end
            if all(obj.ERTName == "")
                obj.ERTName = obj.CIGREName;
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
                leaves = [leaves, [next.getLeaves]];
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
                error("Entry must be scalar or all the same length");
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

        % Output of cigre names allows us to easily keep track of what
        % cigre names have been used in nested structs
        function [objs, usedCIGRENames] = fromDataInterface(dis, modelName, nameroot, nvp)
            arguments
                dis
                modelName (1,1) string = string(nan) % Required to find default param value
                nameroot (1,:) string = string.empty % Allow nested parameter search
                nvp.OverloadStorage (1,1) string = string(nan)
                nvp.UsedCIGRENames (1,:) string = string.empty(1,0)
                nvp.HasDefaultValue (1,1) logical = false 
            end

            objs = cigre.description.Variable.empty(1,0);

            usedCIGRENames = nvp.UsedCIGRENames;


            for i = 1:numel(dis)

                di = dis(i);

                simulinkName = cigre.description.Variable.extractSimulinkName(di);
                ertName = cigre.description.Variable.extractExternalName(di, "NameRoot", nameroot);
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
                if nvp.HasDefaultValue
                    defaultValues = cigre.description.Variable.extractDefaultParamValue(modelName, paramName);
                else
                    defaultValues = [];
                end

                % Determine if the data interface describes a parameter
                % struct
                subCIGRENames = string.empty(1,0);
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
                        try
                            elements = elements.toArray();
                        catch
                            % Not a sequence
                        end
                        % Pass the storage onto the children in the case of
                        % a struct
                        [sub, subCIGRENames] = cigre.description.Variable.fromDataInterface(elements, modelName, [nameroot, simulinkName], ...
                            "OverloadStorage", storage, ...
                            "UsedCIGRENames", usedCIGRENames, ...
                            "HasDefaultValue", nvp.HasDefaultValue);
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

                usedCIGRENames = [usedCIGRENames, subCIGRENames];
                ertName = matlab.lang.makeUniqueStrings(ertName, usedCIGRENames);
                usedCIGRENames = [usedCIGRENames, ertName];

                newObjs = cigre.description.Variable(...
                    "SimulinkName", simulinkName, ...
                    "ERTName", ertName, ...
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

            % Ensure CIGRE names are unique
            cigre_ = string([objs.CIGREName]);
            cigre_ = matlab.lang.makeUniqueStrings(cigre_);
            cigre_ = num2cell(cigre_);
            [objs.CIGREName] = deal(cigre_{:});


        end

    end

    % Methods interacting on coder interface objects
    methods (Static)
        function name = extractSimulinkName(interface)
            arguments
                interface (1,1)
            end

            if isprop(interface, "GraphicalName")
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
            elseif isprop(imp, "GraphcalName")
                name = imp.GraphicalName;
            elseif isprop(imp, "Type")
                % We want the property name
                type = imp.Type;

                while(isa(type, "coder.types.Pointer"))
                    % Drill into pointer
                    type = type.BaseType;
                end

                if isprop(type, "ExternalName")
                    name = type.ExternalName;
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

            value = [1,1];
            if isprop(interface, "Type")
                type = interface.Type;
                if isprop(type, "Dimensions")
                    dims = type.Dimensions;
                    if ismethod(dims, "toArray")
                        dims = dims.toArray();
                    end
                    value = dims;
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
                    try
                        [~, value] = util.findParam(modelName, paramName);
                    catch
                        % Try to extract from a struct
                        p = extractBefore(paramName + ".", ".");
                        [~, value] = util.findParam(modelName, p);
                        f = strsplit(paramName, ".");
                        for i = 2:numel(f)
                            value = value.(f(i));
                        end
                    end
                catch
                    warning("Parameter " + paramName + " not found. Using default value: " + failedValue);
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

