function out = textBoundaryPattern(varargin)
if verLessThan("MATLAB", "9.9")
    out = "";
else
    out = textBoundary;
end
end

