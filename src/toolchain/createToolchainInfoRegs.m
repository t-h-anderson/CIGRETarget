% -------------------------------------------------------------------------
% Create the ToolchainInfoRegistry entries
% -------------------------------------------------------------------------
function configs = createToolchainInfoRegs

here = fileparts(mfilename("fullpath"));

files = dir(here + "/*.mat");

configs = coder.make.ToolchainInfoRegistry.empty(1,0);

for i = 1:numel(files)
    try
        pth = files(i).folder;
        file = files(i).name;
        
        tc = load(fullfile(pth, file)).tc;
        bits = string(extractBetween(file, " x", ".mat"));
        
        configs(i)                       = coder.make.ToolchainInfoRegistry;
        configs(i).Name                  = tc;
        configs(i).FileName              = fullfile(pth, file);
        configs(i).Platform              =  {'win64'};
        
        switch bits
            case "32"
                configs(i).TargetHWDeviceType    = {'Intel->x86-32 (Windows32)','AMD->x86-32 (Windows32)','Generic->Unspecified (assume 32-bit Generic)'};
            case "64"
                configs(i).TargetHWDeviceType    = {'Intel->x86-64 (Windows64)','AMD->x86-64 (Windows64)','Generic->Unspecified (assume 64-bit Generic)'};
        end
        
    catch me
        warning(me.message)
    end
    
end

end