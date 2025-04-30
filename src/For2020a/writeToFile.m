function writeToFile(text, file)

if verLessThan("MATLAB", "9.9")
    fid = fopen(file, 'w');
    if fid == -1
        % fopen failed
    else
        % fopen successful
        for i = 1:numel(text)
            fwrite(fid, text(i) + newline);
        end
        
        fclose(fid);
    end
    
    
    
else
    
   writelines(text, file); 
   
end

end

