function lines = readFromFile(file)

if verLessThan("MATLAB", "9.9")
    fid = fopen(file, 'r');
    if fid == -1
        % Return empty string so callers can handle missing files without errors
        lines = "";
    else
        lines = string.empty(0,1);
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

