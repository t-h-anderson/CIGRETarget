function [wrapperPath, headerDir] = sanitiseLoadlibraryHeader(headerPath)
%SANITISELOADLIBRARYHEADER  Wrap a C header so MATLAB loadlibrary can parse it.
%
%   [wrapperPath, headerDir] = cigre.util.sanitiseLoadlibraryHeader(headerPath)
%
%   Writes a tiny wrapper header in tempdir that #define's the Windows /
%   GCC annotations (__declspec, __cdecl, __stdcall, __fastcall,
%   __attribute__, __forceinline) to nothing and then #include's the
%   original header by absolute path.
%
%   This works around an issue where MATLAB's built-in loadlibrary parser
%   and/or the MinGW thunk compiler reject those tokens on the function
%   prototypes in IEEE_Cigre_DLLInterface.h, producing errors like:
%
%       Failed to parse type '( __cdecl__ )) Model_GetInfo ('
%       expected declaration specifiers before '__attribute__'
%
%   Returned values:
%     wrapperPath  Absolute path to the generated wrapper header.
%     headerDir    Directory of the original header, suitable for passing
%                  as an 'includepath' to loadlibrary so any sibling
%                  headers (e.g. IEEE_Cigre_DLLInterface_types.h) still
%                  resolve.

    headerPath = char(headerPath);
    headerDir  = fileparts(headerPath);

    wrapperPath = fullfile(tempdir, ...
        sprintf('cigre_loadlib_wrapper_%s.h', char(cigre.util.uuid())));

    fid = fopen(wrapperPath, 'w');
    if fid < 0
        error('CIGRE:sanitiseLoadlibraryHeader:WriteFailed', ...
            'Could not write loadlibrary wrapper header at %s', wrapperPath);
    end
    closeFid = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, '#define __declspec(arg)\n');
    fprintf(fid, '#define __cdecl\n');
    fprintf(fid, '#define __stdcall\n');
    fprintf(fid, '#define __fastcall\n');
    fprintf(fid, '#define __attribute__(arg)\n');
    fprintf(fid, '#define __forceinline\n');
    fprintf(fid, '#include "%s"\n', strrep(headerPath, '\', '\\'));
end
