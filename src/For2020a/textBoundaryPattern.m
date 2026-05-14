function out = textBoundaryPattern(opts)
arguments
    opts.LegacyMatlab (1,1) logical = compat.legacyMatlab()
end
if opts.LegacyMatlab
    out = "";
else
    out = textBoundary;
end
end

