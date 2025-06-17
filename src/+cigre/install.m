function tcName = install(nvp)
arguments
    nvp.Toolchain (1,:) string {mustBeMember(nvp.Toolchain, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022', 'MinGW'})}
    nvp.Type (1,1) string {mustBeMember(nvp.Type, ["All", "32", "64"])} = "All"
end

for i = 1:numel(nvp.Toolchain)
    switch nvp.Type
        case "All"
            tcName = makeDLLToolchain( nvp.Toolchain(i), "32");
            tcName(end+1) = makeDLLToolchain( nvp.Toolchain(i), "64"); %#ok<AGROW>
        case "32"
            tcName = makeDLLToolchain( nvp.Toolchain(i), "32");
        case "64"
            tcName = makeDLLToolchain( nvp.Toolchain(i), "64");
    end
end

RTW.TargetRegistry.getInstance('reset');

end

