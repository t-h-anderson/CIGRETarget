classdef tFunctionInterface < matlab.unittest.TestCase
    % Unit tests for cigre.description.FunctionInterface.
    methods (Test)

        % --- Default construction and IsEmpty sentinel ---

        function defaultConstructorProducesEmptyInterface(testCase)
            % IsEmpty must be true for a default interface so callers can use it
            % as a null-object sentinel without any [] vs object checks.
            iface = cigre.description.FunctionInterface();
            testCase.verifyTrue(iface.IsEmpty);
        end

        function interfaceWithNameIsNotEmpty(testCase)
            iface = cigre.description.FunctionInterface("Name", "MyModel_step");
            testCase.verifyFalse(iface.IsEmpty);
        end

        function explicitEmptyNameStringProducesEmptyInterface(testCase)
            % Explicitly setting Name to "" must still be treated as empty so
            % the sentinel behaviour is consistent regardless of construction path.
            iface = cigre.description.FunctionInterface("Name", "");
            testCase.verifyTrue(iface.IsEmpty);
        end

        % --- Named-argument construction ---

        function namedConstructorSetsAllProperties(testCase)
            iface = cigre.description.FunctionInterface(...
                "Name", "Model_Initialize", ...
                "ArgumentNames", ["rtM", "localDW"], ...
                "ArgumentTypes", ["RT_MODEL_T", "DW_Model_T"], ...
                "ArgumentPointers", ["*", "*"]);
            testCase.verifyEqual(iface.Name, "Model_Initialize");
            testCase.verifyEqual(iface.ArgumentNames, ["rtM", "localDW"]);
            testCase.verifyEqual(iface.ArgumentTypes, ["RT_MODEL_T", "DW_Model_T"]);
            testCase.verifyEqual(iface.ArgumentPointers, ["*", "*"]);
        end

        function argumentArraysDefaultToEmptyForNamedInterface(testCase)
            % A named interface with no arguments is valid for zero-argument functions
            % and must not trigger any size-mismatch errors downstream.
            iface = cigre.description.FunctionInterface("Name", "VoidFunc");
            testCase.verifyEmpty(iface.ArgumentNames);
            testCase.verifyEmpty(iface.ArgumentTypes);
            testCase.verifyEmpty(iface.ArgumentPointers);
        end

        function allArgumentArraysHaveMatchingLength(testCase)
            % All three argument arrays must be index-aligned; a mismatch would
            % silently pair the wrong type with the wrong name in the generated C.
            iface = cigre.description.FunctionInterface(...
                "Name", "f", ...
                "ArgumentNames", ["a", "b", "c"], ...
                "ArgumentTypes", ["real_T", "int32_T", "uint8_T"], ...
                "ArgumentPointers", ["*", "*", "*"]);
            n = numel(iface.ArgumentNames);
            testCase.verifyEqual(numel(iface.ArgumentTypes), n, ...
                "ArgumentTypes length must match ArgumentNames");
            testCase.verifyEqual(numel(iface.ArgumentPointers), n, ...
                "ArgumentPointers length must match ArgumentNames");
        end

        % --- fromSourceFile ---

        function fromSourceFileParsesNameAndArguments(testCase)
            buildDir = makeTempSourceFile(testCase, "MyModel", [
                "void MyModel_Initialize(real_T *rtM, DW_MyModel_T *localDW)"
                "{"
                "  rtM->errorStatus = 0;"
                "}"
            ]);
            iface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "MyModel", "Initialize");
            testCase.verifyEqual(iface.Name, "MyModel_Initialize");
            testCase.verifyEqual(iface.ArgumentNames, ["rtM", "localDW"]);
            testCase.verifyEqual(iface.ArgumentTypes, ["real_T", "DW_MyModel_T"]);
        end

        function fromSourceFileParsesMultilineSignature(testCase)
            % Signatures split across lines by code formatters must be joined
            % before parsing so the full argument list is captured.
            buildDir = makeTempSourceFile(testCase, "MyModel", [
                "void MyModel_Initialize(real_T *rtM,"
                "  DW_MyModel_T *localDW)"
                "{"
                "}"
            ]);
            iface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "MyModel", "Initialize");
            testCase.verifyEqual(iface.Name, "MyModel_Initialize");
            testCase.verifyNumElements(iface.ArgumentNames, 2);
        end

        function fromSourceFileReturnsEmptyWhenFunctionAbsent(testCase)
            % A missing function should yield an empty interface rather than an
            % error, because absence is normal for optional entry points.
            buildDir = makeTempSourceFile(testCase, "MyModel", [
                "void MyModel_Step(real_T *rtM)"
                "{"
                "}"
            ]);
            iface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "MyModel", "Initialize");
            testCase.verifyTrue(iface.IsEmpty);
        end

        function fromSourceFileArgumentCountMatchesSignature(testCase)
            buildDir = makeTempSourceFile(testCase, "ThreeArgs", [
                "void ThreeArgs_Initialize(real_T *a, int32_T *b, uint8_T *c)"
                "{"
                "}"
            ]);
            iface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "ThreeArgs", "Initialize");
            testCase.verifyNumElements(iface.ArgumentNames, 3);
            testCase.verifyNumElements(iface.ArgumentTypes, 3);
            testCase.verifyNumElements(iface.ArgumentPointers, 3);
        end

        function fromSourceFileSelectsCorrectEntryPointByFunctionType(testCase)
            % When multiple entry points share a file, the functionType argument
            % must select the correct one without matching the others.
            buildDir = makeTempSourceFile(testCase, "M", [
                "void M_Initialize(real_T *a)"
                "{"
                "}"
                "void M_Terminate(int32_T *b)"
                "{"
                "}"
            ]);
            initIface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "M", "Initialize");
            termIface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "M", "Terminate");
            testCase.verifyEqual(initIface.Name, "M_Initialize");
            testCase.verifyEqual(termIface.Name, "M_Terminate");
        end

        function fromSourceFileStripsPtrPrefixFromArgumentName(testCase)
            % The leading * in a C pointer declaration must be stripped from the
            % argument name so downstream code can use the name as a valid identifier.
            buildDir = makeTempSourceFile(testCase, "M", [
                "void M_Initialize(real_T *ptrArg)"
                "{"
                "}"
            ]);
            iface = cigre.description.FunctionInterface.fromSourceFile(...
                buildDir, "M", "Initialize");
            testCase.verifyEqual(iface.ArgumentNames, "ptrArg");
        end

    end

end

% --- Local helper ---------------------------------------------------------

function buildDir = makeTempSourceFile(testCase, modelName, lines)
    % Write a minimal .c file to a temporary directory and register cleanup.
    buildDir = string(tempname());
    mkdir(buildDir);
    testCase.addTeardown(@() rmdir(buildDir, 's'));
    fid = fopen(fullfile(buildDir, modelName + ".c"), 'w');
    fprintf(fid, '%s\n', lines);
    fclose(fid);
end