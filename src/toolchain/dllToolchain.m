function tc = dllToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022', 'MinGW'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end

switch compilerVersion
    case 'MinGW'
        tc = minGWDLLToolchain(compilerVersion, type);
    otherwise
        tc = msvcToolchain(compilerVersion, type);
end

end
