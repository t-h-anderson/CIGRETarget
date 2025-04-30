function makeDLLToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end

here = fileparts(mfilename("fullpath"));

tc =  dllToolchain( compilerVersion, type );

switch compilerVersion
    case 'Visual C++ 2017'
        ver = "2017";
    case 'Visual C++ 2019'
        ver = "2019";
    case 'Visual C++ 2022'
        ver = "2022";
end

tcName = "CIGRE DLL Toolchain VS" + ver + " x" + type + ".mat";

save(fullfile(here, tcName), "tc");

RTW.TargetRegistry.getInstance('reset');

end

