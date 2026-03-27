function val = extractString(str, arg)

if verLessThan("MATLAB", "9.9")
    if isnumeric(arg)
        val = str{1}(arg);
    else
        error("Not yest supported")
    end
else
    val = extract(str, arg);
end

end

