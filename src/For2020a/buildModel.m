function buildModel(mdlName)
arguments
    mdlName (1,1) string
end

if verLessThan("MATLAB", "9.9")
    % R2020a's slbuild has no generateCodeOnly flag; the hook still
    % fires when a full build is requested and emits the CIGRE source.
    slbuild(mdlName)
else
    cigre.internal.buildCodeOnly(mdlName);
end

end
