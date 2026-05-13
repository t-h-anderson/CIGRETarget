function assertCigreLibraryLoaded(alias, notfound)
% assertCigreLibraryLoaded Verify the five CIGRE Model_* prototypes registered.
%
% loadlibrary will return success on some MATLAB releases (notably R2023b)
% even when the header parser silently bails partway through, dropping
% every typedef and prototype that followed. The failure only surfaces
% later as a cryptic "Type was not found" from libpointer.
%
% Probing the alias for the five Model_* prototypes we actually invoke
% via calllib is sufficient: if the prototypes registered, the
% IEEE_Cigre_DLLInterface_Instance struct they reference must also have
% registered. Anything missing here means the library is unusable, and
% we'd rather error here with the offending list than crash deep inside
% the S-Function later.
arguments
    alias (1,1) string
    notfound (1,:) cell = {}
end

fns = libfunctions(char(alias));
required = ["Model_FirstCall", "Model_CheckParameters", ...
            "Model_Initialize", "Model_Outputs", "Model_Terminate"];
missing = required(~ismember(required, string(fns)));
if isempty(missing)
    return
end

if isempty(notfound)
    extra = "";
else
    extra = " (loadlibrary notfound: " + strjoin(string(notfound), ", ") + ")";
end

error("CIGRE:CigreLibrary:RequiredPrototypesMissing", ...
    "loadlibrary did not register required prototypes %s for alias '%s'%s.", ...
    strjoin(missing, ", "), alias, extra);
end
