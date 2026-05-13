function out = textBoundaryPattern(varargin)
arguments (Repeating)
    varargin
end
if verLessThan("MATLAB", "9.9")
    out = "";
else
    out = textBoundary;
end
end

