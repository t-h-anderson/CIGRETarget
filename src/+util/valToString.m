function str = valToString(s)

if ~isscalar(s)
    sz = size(s);
    if numel(sz) > 2
        error("Tensors not supported");
    end

    p = cell(sz);
    for i = 1:numel(s)
        p{i} = util.valToString(s(i));
    end

    str = "[";
    for i = 1:size(s, 2)
        str = str + strjoin([p{i,:}], ", ");
        
        if i < size(s, 2)
            str = str + "; ";
        end
    end
    str = str + "]";
        

    return
end

str = "";
if isstruct(s)
    str = "struct(";

    fs = string(fields(s));

    for i = 1:numel(fs)
        f = fs(i);

        str = str + """" + f + """, ";

        val = s.(f);
        str = str + util.valToString(val);
        
        if i ~= numel(fs)
            str = str + ", ";
        end

    end

    str = str + ")";
elseif isstring(s) || ischar(s)
    str = """" + s + """";
else
    c = class(s);
    if ~strcmp(c, "double")
        str = str + c + "(" + s + ")";
    else
        str = str + string(s);
    end
end

end