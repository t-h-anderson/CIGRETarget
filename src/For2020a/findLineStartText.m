function idx = findLineStartText(txt, toMatch)

if verLessThan("MATLAB", "9.9")
    idx = find(cellfun(@(x) sum(x) > 0, regexp(txt, "^" + toMatch)));
else
    idx = find(contains(txt, lineBoundary + toMatch));
end


end

