function writeToFile(text, file)
arguments
    text (:,1) string
    file (1,1) string
end

if verLessThan("MATLAB", "9.9")
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
