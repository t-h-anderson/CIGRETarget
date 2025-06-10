function install(nvp)
arguments
    nvp.Toolchain (1,:) string {mustBeMember(nvp.Toolchain, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022', 'MinGW'})}
end

for i = 1:numel(nvp.Toolchain)
    makeDLLToolchain( nvp.Toolchain(i), "32")
    makeDLLToolchain( nvp.Toolchain(i), "64")
end

RTW.TargetRegistry.getInstance('reset');

end

