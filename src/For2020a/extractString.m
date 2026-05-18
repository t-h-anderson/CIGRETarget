function val = extractString(str, arg, opts)
arguments
    str
    arg
    opts.LegacyMatlab (1,1) logical = compat.legacyMatlab()
end

if opts.LegacyMatlab
    if isnumeric(arg)
        val = str{1}(arg);
    else
        error("Pattern-based extract is not supported on MATLAB < R2020b")
    end
else
    val = extract(str, arg);
end

end
