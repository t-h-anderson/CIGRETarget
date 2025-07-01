function toolchainObjectHandle = msvcToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end
% [ toolchainObjectHandle ] = my_msvc_64bit_tc( compilerVersion ) returns a
% coder.make.ToolchainInfo object handle, where the Microsoft Compiler
% Version (compilerVersion) being used is one of the following:
% { 'Visual C++ 2017', 'Visual C++ 2019', 'Visual C++ 2022'}
%
% The general idea is that we need to call the compiler and linker in
% 32-bit mode and feed the correct flags to create a ".dll".
%
% In particular, the string that we assign to "ShellSetup" does NOT include any
% 64-bit-related flags.  The "ShellSetup" is a string that is run in DOS
% and eventually drives the "make" process. In the 64-bit toolchain
% examples elsewhere, this string includes a flag to start the compiler in
% 64-bit mode. By removing the flag, we let the compiler be called in its
% default, 32-bit, mode.


thisFilesFullName = mfilename( 'fullpath' );

preExecutionMessage = ...
    [ 'Executing "', thisFilesFullName, '"...' ];
disp( preExecutionMessage );

compilationPlatform = 'win64';

switch compilationPlatform
    case 'win64'
        % Do nothing
    otherwise
        error( 'This approach is only designed to run on 64-bit Windows.' );
end

name = "CIGRE DLL - Microsoft " + compilerVersion + " (" + type + "bit)";

% Defaults
switch type
    case "32"
        compilerOptionString = ' amd64_x86';
    case "64"
        compilerOptionString = ' amd64';
end

% Construct the toolchain object
toolchainObjectHandle = coder.make.ToolchainInfo( ...
    'Name',                 name + " | nmake makefile (64-bit Windows)", ...
    'BuildArtifact',        'nmake makefile', ...
    'Platform',             compilationPlatform, ...
    'SupportedVersion',     compilerVersion, ...
    'Revision',             '1.0' );

switch( compilerVersion ) 
    case 'Visual C++ 2017'
        compilers = mex.getCompilerConfigurations('C', 'Installed');
        mscv2017 = compilers(ismember({compilers(:).Name}', 'Microsoft Visual C++ 2017 (C)'));
        if isempty(mscv2017)
            error('An installation of Microsoft Visual C++ 2017 cannot be detected');
        end
        compilerPathOperatingSystemEnvironmentVariable  = fullfile(mscv2017.Location);
        compilerSetUpOperatingSystemCommandRelativeName = '\VC\Auxiliary\Build\vcvarsall.bat';
        mexOptsFile = '$(MATLAB_ROOT)\bin\$(ARCH)\mexopts\msvc2017.xml';
        compilerThreadingFlag = '';
        matlabSetupCommand = [];
        matlabCleanupCommand = [ ];
        inlinedCommands = '!include $(MATLAB_ROOT)\rtw\c\tools\vcdefs.mak';
        toolchainObjectHandle.ShellSetup{1} = 'set "VSCMD_START_DIR=%CD%"';
        
    case 'Visual C++ 2019'
        compilers = mex.getCompilerConfigurations('C', 'Installed');
        mscv2019 = compilers(ismember({compilers(:).Name}', 'Microsoft Visual C++ 2019 (C)'));
        if isempty(mscv2019)
            error('An installation of Microsoft Visual C++ 2019 cannot be detected');
        end
        compilerPathOperatingSystemEnvironmentVariable  = fullfile(mscv2019.Location);
        compilerSetUpOperatingSystemCommandRelativeName = '\VC\Auxiliary\Build\vcvarsall.bat';
        mexOptsFile = '$(MATLAB_ROOT)\bin\$(ARCH)\mexopts\msvc2019.xml';
        compilerThreadingFlag = '';
        matlabSetupCommand = [];
        matlabCleanupCommand = [ ];
        inlinedCommands = '!include $(MATLAB_ROOT)\rtw\c\tools\vcdefs.mak';
        toolchainObjectHandle.ShellSetup{1} = 'set "VSCMD_START_DIR=%CD%"';

    case 'Visual C++ 2022'
        compilers = mex.getCompilerConfigurations('C', 'Installed');
        mscv2022 = compilers(ismember({compilers(:).Name}', 'Microsoft Visual C++ 2022 (C)'));
        if isempty(mscv2022)
            error('An installation of Microsoft Visual C++ 2022 cannot be detected');
        end
        compilerPathOperatingSystemEnvironmentVariable  = fullfile(mscv2022.Location);
        compilerSetUpOperatingSystemCommandRelativeName = '\VC\Auxiliary\Build\vcvarsall.bat';
        mexOptsFile = '$(MATLAB_ROOT)\bin\$(ARCH)\mexopts\msvc2022.xml';
        compilerThreadingFlag = '';
        matlabSetupCommand = [];
        matlabCleanupCommand = [ ];
        inlinedCommands = '!include $(MATLAB_ROOT)\rtw\c\tools\vcdefs.mak';
        toolchainObjectHandle.ShellSetup{1} = 'set "VSCMD_START_DIR=%CD%"';
        
    otherwise
        errorMessage = "Version " + compilerVersion + " is not supported.";
        error( errorMessage );
end

% VCVARS
% Issue: VS---COMNTOOLS may or may not have a file separator in the end. How
% do we resolve this on the user's machine?

% NOTE: For 32bit, we are specifically leaving off the usual "AMD64" flag, to start
% Visual Studio in 32-bit mode, despite the fact that this is running on a
% 64-bit installation of MATLAB.

compilerShellSetupOSCommandString = ...
    [ ...
    'call "', ...
    compilerPathOperatingSystemEnvironmentVariable, ...
    compilerSetUpOperatingSystemCommandRelativeName, ...
    '"', ...
    compilerOptionString, ...
    ];

toolchainObjectHandle.InlinedCommands = inlinedCommands;
toolchainObjectHandle.addAttribute( 'TransformPathsWithSpaces' );
toolchainObjectHandle.addAttribute( 'RequiresCommandFile' );
toolchainObjectHandle.addAttribute( 'RequiresBatchFile' );

% For internal use only
toolchainObjectHandle.SupportsBuildingMEXFuncs = true;

toolchainObjectHandle.ShellSetup{ end+1 } = compilerShellSetupOSCommandString;

if( true == isempty( matlabSetupCommand ) )
    % It's OK for this to be empty.
else
    toolchainObjectHandle.MATLABSetup{ 1 } = matlabSetupCommand;
end

if( true == isempty( matlabCleanupCommand )  )
    % It's OK for this to be empty.
else
    toolchainObjectHandle.MATLABCleanup{ 1 } = matlabCleanupCommand;
end


% ------------------------------
% Macros
% ------------------------------

toolchainObjectHandle.addMacro('MEX_OPTS_FILE',    mexOptsFile );
toolchainObjectHandle.addMacro('MDFLAG',           compilerThreadingFlag );
toolchainObjectHandle.addMacro('MW_EXTERNLIB_DIR', [ '$(MATLAB_ROOT)\extern\lib\' compilationPlatform '\microsoft' ] );
toolchainObjectHandle.addMacro('MW_LIB_DIR',       [ '$(MATLAB_ROOT)\lib\' compilationPlatform ] );

toolchainObjectHandle.addIntrinsicMacros( { 'NODEBUG', 'cvarsdll', 'cvarsmt', ...
    'conlibsmt', 'ldebug', 'conflags', 'cflags' } );

% ------------------------------
% C Compiler
% ------------------------------

cBuildToolHandle = toolchainObjectHandle.getBuildTool( 'C Compiler' );

cBuildToolHandle.setName(           'Microsoft Visual C Compiler' );
cBuildToolHandle.setCommand(        'cl' );
cBuildToolHandle.setPath(           '' );

cBuildToolHandle.setDirective(      'IncludeSearchPath',    '-I' );
cBuildToolHandle.setDirective(      'PreprocessorDefine',   '-D' );
cBuildToolHandle.setDirective(      'OutputFlag',           '-Fo' );
cBuildToolHandle.setDirective(      'Debug',                '-Zi' );

cBuildToolHandle.setFileExtension(  'Source',               '.c' );
cBuildToolHandle.setFileExtension(  'Header',               '.h' );
cBuildToolHandle.setFileExtension(  'Object',               '.obj' );

cBuildToolHandle.setCommandPattern( '|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% C++ Compiler
% ------------------------------

cppBuildToolHandle = toolchainObjectHandle.getBuildTool('C++ Compiler' );

cppBuildToolHandle.setName(           'Microsoft Visual C++ Compiler' );
cppBuildToolHandle.setCommand(        'cl' );
cppBuildToolHandle.setPath(           '' );

cppBuildToolHandle.setDirective(      'IncludeSearchPath',    '-I' );
cppBuildToolHandle.setDirective(      'PreprocessorDefine',   '-D' );
cppBuildToolHandle.setDirective(      'OutputFlag',           '-Fo' );
cppBuildToolHandle.setDirective(      'Debug',                '-Zi' );

cppBuildToolHandle.setFileExtension(  'Source',               '.cpp' );
cppBuildToolHandle.setFileExtension(  'Header',               '.hpp' );
cppBuildToolHandle.setFileExtension(  'Object',               '.obj' );

cppBuildToolHandle.setCommandPattern('|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% Linker
% ------------------------------

cLinkToolHandle = toolchainObjectHandle.getBuildTool( 'Linker' );

cLinkToolHandle.setName(           'Microsoft Visual C Linker' );
cLinkToolHandle.setCommand(        'link' );
cLinkToolHandle.setPath(           '' );

cLinkToolHandle.setDirective(      'Library',              '-L' );
cLinkToolHandle.setDirective(      'LibrarySearchPath',    '-I' );
cLinkToolHandle.setDirective(      'OutputFlag',           '-out:' );
cLinkToolHandle.setDirective(      'Debug',                '/DEBUG' );

cLinkToolHandle.setFileExtension(  'Executable',           '.dll' );
cLinkToolHandle.setFileExtension(  'Shared Library',       '.dll' );

cLinkToolHandle.setCommandPattern('|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% C++ Linker
% ------------------------------

cppLinkToolHandle = toolchainObjectHandle.getBuildTool('C++ Linker' );

cppLinkToolHandle.setName(           'Microsoft Visual C++ Linker' );
cppLinkToolHandle.setCommand(        'link' );
cppLinkToolHandle.setPath(           '' );

cppLinkToolHandle.setDirective(      'Library',              '-L' );
cppLinkToolHandle.setDirective(      'LibrarySearchPath',    '-I' );
cppLinkToolHandle.setDirective(      'OutputFlag',           '-out:' );
cppLinkToolHandle.setDirective(      'Debug',                '/DEBUG' );

cppLinkToolHandle.setFileExtension(  'Executable',           '.dll' );
cppLinkToolHandle.setFileExtension(  'Shared Library',       '.dll' );

cppLinkToolHandle.setCommandPattern('|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% Archiver
% ------------------------------

archiverToolHandle = toolchainObjectHandle.getBuildTool( 'Archiver' );

archiverToolHandle.setName(           'Microsoft Visual C/C++ Archiver' );
archiverToolHandle.setCommand(        'lib' );
archiverToolHandle.setPath(           '' );

archiverToolHandle.setDirective(      'OutputFlag',           '-out:' );

archiverToolHandle.setFileExtension(  'Static Library',       '.lib' );

archiverToolHandle.setCommandPattern( '|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% Builder
% ------------------------------

toolchainObjectHandle.setBuilderApplication( compilationPlatform );

% --------------------------------------------
% BUILD CONFIGURATIONS
% --------------------------------------------

% ------------------------------
% Compiler optimization flags
% ------------------------------

% Optimization Level = Off is obtained from Microsoft's website:
%   http://msdn2.microsoft.com/en-us/library/fwkeyyhe(VS.71).aspx
optimsOffOpts = { '/Od /Oy-' };

% Optimization Level = On is obtained from mexopts files:
%   <matlabroot>/bin/win32/mexopts/msvc60opts.bat
%   <matlabroot>/bin/win32/mexopts/msvc71opts.bat
%   <matlabroot>/bin/win32/mexopts/msvc80opts.bat
%   <matlabroot>/bin/win32/mexopts/msvc80freeopts.bat
optimsOnOpts = { '/O2 /Oy-' };

% ------------------------------
% Macros
% ------------------------------

switch type
    case "32"
        toolchainObjectHandle.addMacro( 'CPU', 'X86');
    case "64"
        toolchainObjectHandle.addMacro( 'CPU', 'AMD64');
end

% # Uncomment this line to move warning level to W4
% # cflags = $(cflags:W3=W4)

cvarsflag = '$(cvarsmt)';
toolchainObjectHandle.addMacro( 'CVARSFLAG', cvarsflag );

CFLAGS_ADDITIONAL   = '-D_CRT_SECURE_NO_WARNINGS';
CPPFLAGS_ADDITIONAL = '-EHs -D_CRT_SECURE_NO_WARNINGS';
LIBS_TOOLCHAIN = '$(conlibs)';
toolchainObjectHandle.addMacro( 'CFLAGS_ADDITIONAL',   CFLAGS_ADDITIONAL );
toolchainObjectHandle.addMacro( 'CPPFLAGS_ADDITIONAL', CPPFLAGS_ADDITIONAL );
toolchainObjectHandle.addMacro( 'LIBS_TOOLCHAIN',      LIBS_TOOLCHAIN );

cCompilerOpts    = '$(cflags) $(CVARSFLAG) $(CFLAGS_ADDITIONAL)';
cppCompilerOpts  = '/TP $(cflags) $(CVARSFLAG) $(CPPFLAGS_ADDITIONAL)';

switch type
    case "32"
        linkerOpts       = { '/MACHINE:X86 $(ldebug) $(conflags) $(LIBS_TOOLCHAIN)' };
    case "64"
        linkerOpts       = { '/MACHINE:X64 $(ldebug) $(conflags) $(LIBS_TOOLCHAIN)' };
end

sharedLinkerOpts = horzcat(linkerOpts, '-dll'); % -def:$(DEF_FILE)' ); % TODO; Removed this. Do we ever want to supply this?
archiverOpts     = { '/nologo' };

% Get the debug flag per build tool
debugFlag.CCompiler    = getDebugFlag( 'C Compiler' );
debugFlag.CppCompiler  = getDebugFlag( 'C++ Compiler' );
debugFlag.Linker       = getDebugFlag( 'Linker' );
debugFlag.Archiver     = getDebugFlag( 'Archiver' );

buildConfigurationObject = toolchainObjectHandle.getBuildConfiguration( 'Faster Builds' );
buildConfigurationObject.setOption( 'C Compiler',                horzcat( cCompilerOpts, optimsOffOpts ) );
buildConfigurationObject.setOption( 'C++ Compiler',              horzcat( cppCompilerOpts, optimsOffOpts ) );
buildConfigurationObject.setOption( 'Linker',                    sharedLinkerOpts ); % linkerOpts
buildConfigurationObject.setOption( 'C++ Linker',                sharedLinkerOpts ); % linkerOpts
buildConfigurationObject.setOption( 'Shared Library Linker',     sharedLinkerOpts );
buildConfigurationObject.setOption( 'C++ Shared Library Linker', sharedLinkerOpts );
buildConfigurationObject.setOption( 'Archiver',                  archiverOpts );

buildConfigurationObject = toolchainObjectHandle.getBuildConfiguration( 'Faster Runs' );
buildConfigurationObject.setOption( 'C Compiler',                horzcat( cCompilerOpts, optimsOnOpts ) );
buildConfigurationObject.setOption( 'C++ Compiler',              horzcat( cppCompilerOpts, optimsOnOpts ) );
buildConfigurationObject.setOption( 'Linker',                    sharedLinkerOpts ); % linkerOpts
buildConfigurationObject.setOption( 'C++ Linker',                sharedLinkerOpts ); % linkerOpts
buildConfigurationObject.setOption( 'Shared Library Linker',     sharedLinkerOpts );
buildConfigurationObject.setOption( 'C++ Shared Library Linker', sharedLinkerOpts );
buildConfigurationObject.setOption( 'Archiver',                  archiverOpts );

buildConfigurationObject = toolchainObjectHandle.getBuildConfiguration( 'Debug' );
buildConfigurationObject.setOption( 'C Compiler',                    horzcat( cCompilerOpts, optimsOffOpts, debugFlag.CCompiler ) );
buildConfigurationObject.setOption( 'C++ Compiler',                  horzcat( cppCompilerOpts, optimsOffOpts, debugFlag.CppCompiler ) );
buildConfigurationObject.setOption( 'Linker',                        horzcat( sharedLinkerOpts,       debugFlag.Linker ) ); % linkerOpts
buildConfigurationObject.setOption( 'C++ Linker',                    horzcat( sharedLinkerOpts,       debugFlag.Linker ) ); % linkerOpts
buildConfigurationObject.setOption( 'Shared Library Linker',         horzcat( sharedLinkerOpts, debugFlag.Linker ) );
buildConfigurationObject.setOption( 'C++ Shared Library Linker',     horzcat( sharedLinkerOpts, debugFlag.Linker ) );
buildConfigurationObject.setOption( 'Archiver',                      horzcat( archiverOpts,     debugFlag.Archiver ) );

toolchainObjectHandle.setBuildConfigurationOption( 'all', 'Download',      '' );
toolchainObjectHandle.setBuildConfigurationOption( 'all', 'Execute',       '' );
toolchainObjectHandle.setBuildConfigurationOption( 'all', 'Make Tool',     '-f $(MAKEFILE)' );

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Helper Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    function [ flag ] = getDebugFlag( toolkey )
        flag = toolchainObjectHandle.getBuildTool( toolkey ).Directives.getValue( 'Debug' ).getRef( );
        return;
    end


postExecutionMessage = ...
    [ 'Executed "', thisFilesFullName, '".' ];
disp( postExecutionMessage );

return;

end
