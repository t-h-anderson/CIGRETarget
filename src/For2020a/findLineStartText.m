function [idxs, idx] = findLineStartText(txt, toMatch, opts)
arguments
    txt (:,1) string
    toMatch (1,1) string
    opts.LegacyMatlab (1,1) logical = compat.legacyMatlab()
end

if opts.LegacyMatlab
    idx = cellfun(@(x) sum(x) > 0, regexp(txt, "^" + toMatch));
else
    idx = contains(txt, lineBoundary + toMatch);
end

idxs = find(idx);

end

