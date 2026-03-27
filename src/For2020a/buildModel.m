function buildModel(mdlName)

if verLessThan("MATLAB", "9.9")
    % TODO: how do we do code only?
    slbuild(mdlName)
else
    cigre.internal.buildCodeOnly(mdlName);
end

end

