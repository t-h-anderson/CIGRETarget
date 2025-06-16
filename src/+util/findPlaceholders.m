function found = findPlaceholders(filename)

found = {};
for i = 1:numel(filename)
txt = readlines(filename{i});
txt = strjoin(txt, newline);

found{i} = extract(txt, "<<" + wildcardPattern("Except", "<>") + ">>");
end

found = vertcat(found{:});

found = unique(found);
end

