function buildModel(mdlName)

if verLessThan("MATLAB", "9.9")
    % TODO: how do we do code only?
    slbuild(mdlName)
else
    
    slbuild(mdlName, 'GenerateCodeOnly', true)
    
end

end

