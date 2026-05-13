function val = extractString(str, arg)
arguments
    str
    arg
end

if verLessThan("MATLAB", "9.9")
    if isnumeric(arg)
        val = str{1}(arg);
    else
        error("Pattern-based extract is not supported on MATLAB < R2020b")
    end
else
    val = extract(str, arg);
end

end
