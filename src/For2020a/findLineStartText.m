function [idxs, idx] = findLineStartText(txt, toMatch)
arguments
    txt (:,1) string
    toMatch (1,1) string
end

if verLessThan("MATLAB", "9.9")
    idx = cellfun(@(x) sum(x) > 0, regexp(txt, "^" + toMatch));
else
    idx = contains(txt, lineBoundary + toMatch);
end

idxs = find(idx);

end

