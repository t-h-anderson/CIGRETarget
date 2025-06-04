function toolchainObjectHandle = dllToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022', 'MinGW'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end

switch compilerVersion
    case 'MinGW'
        toolchainObjectHandle = minGWDLLToolchain(compilerVersion, type);
    otherwise
        toolchainObjectHandle = msvcToolchain(compilerVersion, type);
end

end
