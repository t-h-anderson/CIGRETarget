classdef CigreDLL < handle

    properties
        IsLoaded (1,1) logical = false
        Name (1,1) string
        Header (1,1) string
    end

    properties (Hidden)
        Name_ (1,1) string = ""
    end

    methods
        function obj = CigreDLL(dllName, nvp)
            arguments
                dllName (1,1) string
                nvp.Header (1,1) string = "IEEE_Cigre_DLLInterface.h"
            end
            dllName = erase(dllName, ".dll");
            hfile = nvp.Header;

            obj.Name = dllName;
            obj.Header = hfile;

            % loadlibrary uses the alias as the global library handle,
            % so a UUID suffix lets multiple instances of the same DLL
            % coexist in one MATLAB session.
            thisDLL = dllName + cigre.util.uuid();
            obj.Name_ = thisDLL;
        end

        function cleanObj = load(obj)

            dllName = obj.Name + ".dll";
            thisDLL = obj.Name_;
            hfile = obj.Header;

            unloadIfLoaded(thisDLL);

            if nargout > 0
                cleanObj = @() obj.unload();
            end

            src = fullfile(cigreRoot, "src", "CIGRESource");
            header = fullfile(src, hfile);
            [wrapperHeader, headerDir] = ...
                cigre.util.sanitiseLoadlibraryHeader(header);
            [notfound, warnings] = loadlibrary(dllName, char(wrapperHeader), ...
                "includepath", src, ...
                "includepath", headerDir, ...
                "alias", thisDLL);

            % Surface a clear error if the header parse dropped the
            % Instance struct or any Model_* prototype - loadlibrary
            % itself does not throw in that case.
            cigre.util.assertCigreLibraryLoaded(thisDLL, notfound);

            obj.IsLoaded = true;

        end

        function results = run(obj, input, nvp)
            % Step the model forward NSteps times and return only the
            % final outputs; useful for advancing a fresh instance past
            % the first-call transient.
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

            calllib(obj.Name_, "Model_Initialize", data);

            input.IsInitialised = true;

        end

        function input = firstCall(obj, input)

            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
            end

            data = input.Instance;

            calllib(obj.Name_, "Model_FirstCall", data);

        end

        function result = step(obj, input)
            arguments
                obj
                input (1,1) cigre.dll.InterfaceInstance
            end

            data = input.Instance;

            calllib(obj.Name_, "Model_Outputs", data);

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
arguments
    dllName (1,1) string
end
if libisloaded(dllName)
    try
        unloadlibrary(dllName)
    catch me
        disp("Warning: failed to unload library '" + dllName + "': " + me.message)
    end
end
end

