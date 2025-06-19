function [ name ] = minGWDLLToolchain( compilerVersion, type )
arguments
    compilerVersion (1,1) string {mustBeMember(compilerVersion, { 'MinGW'})}
    type (1,1) string {mustBeMember(type, ["32", "64"])}
end

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

name = "MinGW64 (" + type + "bit) DLL";

% Defaults
switch type
    case "32"
        ...error("32bit MinGW not supported yet")
        compilerOptionString = ' -m32';
    case "64"
        compilerOptionString = ' -m64';
end

% Construct the toolchain object
name = "CIGRE DLL - " + name + " | gmake (" + type + "-bit Windows)";
toolchainObjectHandle = coder.make.ToolchainInfo( ...
    'Name',                 name, ...
    'BuildArtifact',        'gmake makefile', ...
    'Platform',             compilationPlatform, ...
    'SupportedVersion',     compilerVersion, ...
    'Revision',             '1.0' );

switch( compilerVersion ) 
    case 'MinGW'
        compilers = mex.getCompilerConfigurations('C', 'Installed');
        minGW = compilers(ismember({compilers(:).Name}', 'MinGW64 Compiler (C)'));
        if isempty(minGW)
            error('An installation of MinGW' + type + ' cannot be detected');
        end
        compilerPathOperatingSystemEnvironmentVariable  = fullfile(minGW.Location);
        compilerSetUpOperatingSystemCommandRelativeName = '\bin\gcc.exe';
        mexOptsFile = '$(MATLAB_ROOT)\bin\$(ARCH)\mexopts\mingw64.xml';
        compilerThreadingFlag = '';
        matlabSetupCommand = [];
        matlabCleanupCommand = [ ];
        ...inlinedCommands = '!include $(MATLAB_ROOT)\rtw\c\tools\vcdefs.mak';
        ...toolchainObjectHandle.ShellSetup{1} = 'set "VSCMD_START_DIR=%CD%"';
        
    otherwise
        errorMessage = "Version " + compilerVersion + " is not supported.";
        error( errorMessage );
end

compilerShellSetupOSCommandString = ...
    [ ...
    'call "', ...
    compilerPathOperatingSystemEnvironmentVariable, ...
    compilerSetUpOperatingSystemCommandRelativeName, ...
    '"', ...
    compilerOptionString, ...
    ];

...toolchainObjectHandle.InlinedCommands = inlinedCommands;
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
toolchainObjectHandle.addMacro('MW_EXTERNLIB_DIR', [ '$(MATLAB_ROOT)\extern\lib\' compilationPlatform '\mingw64' ] );
toolchainObjectHandle.addMacro('MW_LIB_DIR',       [ '$(MATLAB_ROOT)\lib\' compilationPlatform ] );

toolchainObjectHandle.addIntrinsicMacros( { 'NODEBUG', 'cvarsdll', 'cvarsmt', ...
    'conlibsmt', 'ldebug', 'conflags', 'cflags' } );

% ------------------------------
% C Compiler
% ------------------------------

cBuildToolHandle = toolchainObjectHandle.getBuildTool( 'C Compiler' );

cBuildToolHandle.setName(           'MinGW64 - GCC C Compiler' );
cBuildToolHandle.setCommand(        'gcc' );
cBuildToolHandle.setPath(           '' );

cBuildToolHandle.setDirective(      'IncludeSearchPath',    '-I' );
cBuildToolHandle.setDirective(      'PreprocessorDefine',   '-D' );
cBuildToolHandle.setDirective(      'OutputFlag',           '-o' );
cBuildToolHandle.setDirective(      'Debug',                '-g' );

cBuildToolHandle.setFileExtension(  'Source',               '.c' );
cBuildToolHandle.setFileExtension(  'Header',               '.h' );
cBuildToolHandle.setFileExtension(  'Object',               '.obj' );

cBuildToolHandle.setCommandPattern( '|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% C++ Compiler
% ------------------------------

cppBuildToolHandle = toolchainObjectHandle.getBuildTool('C++ Compiler' );

cppBuildToolHandle.setName(           'MinGW - GCC C++ Compiler' );
cppBuildToolHandle.setCommand(        'g++' );
cppBuildToolHandle.setPath(           '' );

cppBuildToolHandle.setDirective(      'IncludeSearchPath',    '-l' );
cppBuildToolHandle.setDirective(      'PreprocessorDefine',   '-D' );
cppBuildToolHandle.setDirective(      'OutputFlag',           '-o' );
cppBuildToolHandle.setDirective(      'Debug',                '-g' );

cppBuildToolHandle.setFileExtension(  'Source',               '.cpp' );
cppBuildToolHandle.setFileExtension(  'Header',               '.hpp' );
cppBuildToolHandle.setFileExtension(  'Object',               '.obj' );

cppBuildToolHandle.setCommandPattern('|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% Linker
% ------------------------------

cLinkToolHandle = toolchainObjectHandle.getBuildTool( 'Linker' );

cLinkToolHandle.setName(           'MinGW - GCC C Linker' );
cLinkToolHandle.setCommand(        'gcc' );
cLinkToolHandle.setPath(           '' );

cLinkToolHandle.setDirective(      'Library',              '-l' );
cLinkToolHandle.setDirective(      'LibrarySearchPath',    '-l' );
cLinkToolHandle.setDirective(      'OutputFlag',           '-o' );
...cLinkToolHandle.setDirective(      'Debug',                '/DEBUG' );

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
cppLinkToolHandle.setDirective(      'LibrarySearchPath',    '-v' );
cppLinkToolHandle.setDirective(      'OutputFlag',           '-out:' );
cppLinkToolHandle.setDirective(      'Debug',                '/DEBUG' );

cppLinkToolHandle.setFileExtension(  'Executable',           '.dll' );
cppLinkToolHandle.setFileExtension(  'Shared Library',       '.dll' );

cppLinkToolHandle.setCommandPattern('|>TOOL<| |>TOOL_OPTIONS<| |>OUTPUT_FLAG<||>OUTPUT<|' );

% ------------------------------
% Archiver
% ------------------------------

archiverToolHandle = toolchainObjectHandle.getBuildTool( 'Archiver' );

archiverToolHandle.setName(           'MinGW: ar Archiver' );
archiverToolHandle.setCommand(        'ar' );
archiverToolHandle.setPath(           '' );

archiverToolHandle.setDirective(      'OutputFlag',           '-q ' );

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
optimsOffOpts = { '-O' };
optimsOnOpts = { '-O0' };

% ------------------------------
% Macros
% ------------------------------

% switch type
%     case "32"
%         toolchainObjectHandle.addMacro( 'CPU', 'X86');
%     case "64"
%         toolchainObjectHandle.addMacro( 'CPU', 'AMD64');
% end

% # Uncomment this line to move warning level to W4
% # cflags = $(cflags:W3=W4)

cvarsflag = '$(cvarsmt)';
toolchainObjectHandle.addMacro( 'CVARSFLAG', cvarsflag );

CFLAGS_ADDITIONAL   = '-c -D_CRT_SECURE_NO_WARNINGS';
CPPFLAGS_ADDITIONAL = '-EHs -D_CRT_SECURE_NO_WARNINGS';
LIBS_TOOLCHAIN = '$(conlibs)';
toolchainObjectHandle.addMacro( 'CFLAGS_ADDITIONAL',   CFLAGS_ADDITIONAL );
toolchainObjectHandle.addMacro( 'CPPFLAGS_ADDITIONAL', CPPFLAGS_ADDITIONAL );
toolchainObjectHandle.addMacro( 'LIBS_TOOLCHAIN',      LIBS_TOOLCHAIN );

cCompilerOpts    = '$(cflags) $(CVARSFLAG) $(CFLAGS_ADDITIONAL)';
cppCompilerOpts  = '-c $(cflags) $(CVARSFLAG) $(CPPFLAGS_ADDITIONAL)';

switch type
    case "32"
        linkerOpts       = { '-m32 $(ldebug) $(conflags) $(LIBS_TOOLCHAIN)' };
    case "64"
        linkerOpts       = { '-m64 $(ldebug) $(conflags) $(LIBS_TOOLCHAIN)' };
end

sharedLinkerOpts = horzcat(linkerOpts); %, '-shared'); % -def:$(DEF_FILE)' ); % TODO; Removed this. Do we ever want to supply this?
archiverOpts     = { '' };

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
