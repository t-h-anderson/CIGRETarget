function str = valToString(s)

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