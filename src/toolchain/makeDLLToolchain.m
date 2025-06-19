function tc = makeDLLToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022', 'MinGW'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end

here = fileparts(mfilename("fullpath"));

tc =  dllToolchain( compilerVersion, type );

switch compilerVersion
    case 'Visual C++ 2017'
        ver = "VS2017";
    case 'Visual C++ 2019'
        ver = "VS2019";
    case 'Visual C++ 2022'
        ver = "VS2022";
    case 'MinGW'
        ver = "MinGW";
end

tcName = "CIGRE DLL Toolchain " + ver + " x" + type + ".mat";

save(fullfile(here, tcName), "tc");

RTW.TargetRegistry.getInstance('reset');

end

