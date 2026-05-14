function buildModel(mdlName, opts)
arguments
    mdlName (1,1) string
    opts.LegacyMatlab (1,1) logical = compat.legacyMatlab()
end

if opts.LegacyMatlab
    % R2020a's slbuild has no generateCodeOnly flag; the hook still
    % fires when a full build is requested and emits the CIGRE source.
    slbuild(mdlName)
else
    cigre.internal.buildCodeOnly(mdlName);
end

end
