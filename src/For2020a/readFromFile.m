function lines = readFromFile(file)
arguments
    file (1,1) string
end

if verLessThan("MATLAB", "9.9")
    fid = fopen(file, "r");
    if fid == -1
        % Return an empty string so callers can detect a missing file
        % via lines == "" without having to wrap each call in try/catch.
        lines = "";
    else
        lines = string.empty(0, 1);
        tline = fgetl(fid);
        while ischar(tline)
            lines = [lines; string(tline)]; %#ok<AGROW>
            tline = fgetl(fid);
        end

        fclose(fid);
    end

else
    lines = readlines(file);
end

end
