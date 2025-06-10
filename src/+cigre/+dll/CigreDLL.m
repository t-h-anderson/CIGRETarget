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
                nvp.Header (1,1) string = "IEEE_Cigre_DLLInterface.h" % erase(dllName, ".dll") + ".h"
            end
            dllName = erase(dllName, ".dll");
            hfile = nvp.Header;

            obj.Name = dllName;
            obj.Header = hfile;

            thisDLL = dllName + matlab.lang.internal.uuid();
            obj.Name_ = thisDLL;
        end

        function cleanObj = load(obj)

            dllName = obj.Name + ".dll";
            thisDLL = obj.Name_;
            hfile = obj.Header;

            unloadIfLoaded(thisDLL);
           
            % Load the dll
            if nargout > 0
                cleanObj = @() obj.unload();
            end

            src = fullfile(cigreRoot, "src", "CIGRESource");
            header = fullfile(src, hfile);
            [l, w] = loadlibrary(dllName, header, ...
                "includepath", src, "alias", thisDLL); %#ok<ASGLU>

            obj.IsLoaded = true;

        end

        function results = run(obj, input, nvp)
            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
                nvp.NSteps (1,1) double {mustBePositive} = 1
            end

            if ~input.IsInitialised
                obj.initialise(input);
            end

            for i = 1:nvp.NSteps
                results = step(obj, input);
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
        
        function delete(obj)
            obj.unload();
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

