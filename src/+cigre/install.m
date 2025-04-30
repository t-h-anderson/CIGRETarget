function install(nvp)
arguments
    nvp.VSVersion (1,:) string {mustBeMember(nvp.VSVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022'})}
end

for i = 1:numel(nvp.VSVersion)
    makeDLLToolchain( nvp.VSVersion(i), "32")
    makeDLLToolchain( nvp.VSVersion(i), "64")
end

RTW.TargetRegistry.getInstance('reset');

end

