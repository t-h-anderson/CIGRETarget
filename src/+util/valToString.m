function str = valToString(val)
% valToString converts a scalar, matrix, or struct into MATLAB-evaluable
% source text. Used when emitting default parameter values into Simulink
% InstanceParameters and CIGRE descriptions, where the receiver expects a
% literal that can be eval'd back to the original value.
arguments
    val
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
    c = string(class(val));
    % shortestExact keeps already-short values short (3.14 stays "3.14")
    % while preserving full precision when it is needed - string() and
    % num2str() silently truncate to ~5 significant figures.
    numText = shortestExact(val);
    if c ~= "double"
        % Wrap non-double numeric literals with a cast so the eval'd value
        % round-trips back to the same class (Simulink defaults to double).
        str = str + c + "(" + numText + ")";
    else
        str = str + numText;
    end
end

end


function txt = shortestExact(val)
% Shortest decimal text for a numeric scalar that still converts back to
% the exact same value and class. Picks the fewest significant figures
% that round-trip, so clean values stay clean without the precision loss
% of string() / num2str().
arguments
    val (1,1)
end
for precision = 1:17
    txt = string(sprintf("%.*g", precision, val));
    if isequaln(cast(str2double(txt), class(val)), val)
        return
    end
end
end