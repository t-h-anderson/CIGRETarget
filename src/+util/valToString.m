function str = valToString(val)
% Take "any" input and convert it to a string
arguments
    val % Could be anything
end

if ~isscalar(val)
    sz = size(val);
    if numel(sz) > 2
        error("Tensors not supported");
    end

    p = cell(sz);
    for i = 1:numel(val)
        p{i} = util.valToString(val(i));
    end

    str = "[";
    for i = 1:size(val, 1)
        str = str + strjoin([p{i,:}], ", ");
        
        % Not the final row, so add a semicolon
        if i < size(val, 1)
            str = str + "; ";
        end
    end
    str = str + "]";
        
    return
end

str = "";
if isstruct(val)
    str = "struct(";

    fs = string(fields(val));

    for i = 1:numel(fs)
        f = fs(i);

        str = str + """" + f + """, ";

        fieldVal = val.(f);
        str = str + util.valToString(fieldVal);
        
        if i ~= numel(fs)
            str = str + ", ";
        end

    end

    str = str + ")";
elseif isstring(val) || ischar(val)
    str = """" + val + """";
else
    c = class(val);
    if ~strcmp(c, "double")
        str = str + c + "(" + val + ")";
    else
        str = str + string(val);
    end
end

end