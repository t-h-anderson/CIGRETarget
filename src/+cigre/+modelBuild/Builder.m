classdef Builder
    
    properties
        CIGRESrcFolder
        BuildFolder
        TargetName (1,1) string = "cigre"
    end
    
    methods
        function obj = Builder(nvp)
            arguments
                nvp.BuildFolder = ""
                nvp.CIGRESourceFolder = fullfile(cigreRoot(), "src", "CIGRESource")
                nvp.TargetName = "cigre"
            end

            obj.CIGRESrcFolder = nvp.CIGRESourceFolder;
            obj.BuildFolder = nvp.BuildFolder;
            obj.TargetName = nvp.TargetName;

        end
        
        function include = build(obj, modelName, nvp)
            arguments
                obj
                modelName
                nvp =[]
            end

            codeGenFolder =  RTW.getBuildDir(modelName).CodeGenFolder;
            cigreSourceFolder = obj.CIGRESrcFolder;
            buildDir =  pwd + "\slprj";

            here = pwd;
            cObj = onCleanup(@() cd(here));
            cd(buildDir);

            cSource = dir(fullfile(cigreSourceFolder, "*.c"));
            cSource = fullfile(string({cSource.folder}), string({cSource.name}));

            % Add folders for model references and sharedutils
            ertdir = fullfile(codeGenFolder, "slprj", obj.TargetName);
            modelFiles = dir(fullfile(ertdir, "**", "*.c"));
            cModel = fullfile(string({modelFiles.folder}), string({modelFiles.name}));

            cBuild = [cModel cSource];      

            sharedUtilsFolder = fullfile(ertdir, "_sharedutils");
            includeFolders = [sharedUtilsFolder, string({modelFiles.folder})];

            include = " -I" + cigreSourceFolder + ""  ...
                + ..." -I" + buildDir + ...
                " " + strjoin("-I" + includeFolders, " ");
            
            include = include + " -I""" + fullfile(matlabroot, "extern", "include") + """";
            
            system("gcc -g -O0 -c " + modelName + "_CIGRE.c" + include);

            % This is now done as a model reference
            %system("gcc -g -O0 -c " + fullfile(buildDir, modelName + ".c") + include);

            % Build model references
            toInclude = "";
            for i = 1:numel(cBuild)
                thisC = cBuild(i);
                system("gcc -g -O0 -c " + thisC + include);

                [~, objfile] = fileparts(thisC);
                objfile  = objfile + ".o";

                toInclude = toInclude + " " + objfile;
            end

            % system("gcc -g -O0 -c " + other + include);
            % toInclude = toInclude + " params.o";

            dll = modelName + "_CIGRE.dll";

            cmd = "gcc -g -O0 -shared -o " + dll + " " + modelName + "_CIGRE.o " + toInclude;
            system(cmd);

            dll = which(dll);
        end
    end
end

