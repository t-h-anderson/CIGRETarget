function writeToFile(text, file)
arguments
    text (:,1) string
    file (1,1) string
end

% writelines was introduced in R2022a (9.12); on every earlier
% release fall back to manual fopen/fwrite. readlines (used in the
% sibling readFromFile.m) came in R2020b so its gate stays at 9.9.
if verLessThan("MATLAB", "9.12")
    fid = fopen(file, "w");
    if fid ~= -1
        for i = 1:numel(text)
            fwrite(fid, text(i) + newline);
        end
        fclose(fid);
    end
else
    writelines(text, file);
end

end
