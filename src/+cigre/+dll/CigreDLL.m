classdef CigreDLL < handle

    properties
        IsLoaded (1,1) logical = false
        Name (1,1) string
        Header (1,1) string
    end

    properties (Hidden)
        Name_
    end

    methods
        function obj = CigreDLL(dllName, nvp)
            arguments
                dllName (1,1) string
                nvp.Header (1,1) string = erase(dllName, ".dll") + ".h"
            end
            dllName = erase(dllName, ".dll");
            hfile = nvp.Header;

            obj.Name = dllName;
            obj.Header = hfile;

            thisDLL = dllName + matlab.lang.internal.uuid();
            obj.Name_ = thisDLL;
        end

        function cleanObj = load(obj)

            dllName = obj.Name;
            thisDLL = obj.Name_;
            hfile = obj.Header;

            unloadIfLoaded(thisDLL);

            here = Simulink.fileGenControl('getConfig').CodeGenFolder;
            src = fullfile(cigreRoot, "src", "CIGRESource");
            shared = fullfile(here, "slprj", "cigre", "_sharedutils");
            refmdlfolder = genpath(fullfile(here));
            refmdlfolder = string(strsplit(refmdlfolder, ";"));

            lcc = string.empty(1,0);
 %            lcc = fullfile(matlabroot, "sys\lcc\include");
%             tcc = fullfile(matlabroot, "sys\tcc\win64\include");
%             
            simulink = fullfile(matlabroot, "simulink\include");
            rtw = fullfile(matlabroot, "rtw\c\src"); 

            paths = [src, shared, refmdlfolder, lcc, simulink, rtw];
            paths = paths(paths ~= "");
            paths = [repelem("includepath", 1, numel(paths)); paths];

            % Load the dll
            if nargout > 0
                cleanObj = @() obj.unload();
            end

            [~, w] = loadlibrary(dllName, hfile, ...
                paths{:}, ...
                "alias", thisDLL);

            obj.IsLoaded = true;

        end

        function results = run(obj, input, nvp)
            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
                nvp.NSteps
            end

            if ~input.IsInitialised
                obj.initialise(input);
            end

            for i = 1:nvp.NSteps
                result = step(obj, input);
            end

        end

        function initialise(obj, input)
            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
            end

            data = input.Instance;

            calllib(obj.Name_,'Model_Initialize', data);

            input.IsInitialised = true;

        end

        function input = firstCall(obj, input)

            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
            end

            data = input.Instance;

            calllib(obj.Name_,'Model_FirstCall', data);

        end

        function result = step(obj, input)
            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
            end

            data = input.Instance;

            calllib(obj.Name_,'Model_Outputs', data);

            result = input.getOutput();

        end

        function unload(obj)
            unloadIfLoaded(obj.Name_);
            obj.IsLoaded = false;
        end

    end

end

function unloadIfLoaded(dllName)
if libisloaded(dllName)
    try
        unloadlibrary(dllName)
    catch me
        display(me.message)
    end
end
end

