function cigre_callback_handler(hDlg, hSrc, action)
% cigre_callback_handler
% Group all settings for the target into one place. Sets default options
% and locks the ones the user must not change.
%
% Copyright 2024 The MathWorks, Inc.

switch string(action)
    case "select"
        general_settings;

    case "activate"
        general_settings;

    case "postapply"
        % No post-apply work required; reserved for future extensions.

    otherwise
        error("Unknown action >%s<.\n", action);
end


    function general_settings
        % Ordering matters: SolverType must be set before Solver because
        % it constrains the allowed list, and the default solver
        % (variable-step) is incompatible with FixedStepDiscrete.

        setve("SolverType", "Fixed-step", false);

        % Hardware - default is 64 bit. Change to 32-bit manually if needed.
        setve("ProdHWDeviceType", "x86-64 (Windows64)", true);

        setve("ZeroInternalMemoryAtStartup", false, false)
        setve("ZeroExternalMemoryAtStartup", false, false)

        % MATLAB enforces a 31-character identifier limit for PSCAD; CIGRE
        % itself does not, and the wrapper renames as needed, so suppress
        % the warning rather than truncate.
        setve("ModelReferenceSymbolNameMessage", "none", true)

        % Force CodeInfo generation; in newer RTW releases this is the
        % default but older releases need it set explicitly.
        setve("GenerateCodeInfo", "on", true);

        % CIGRE DLLs must be reentrant.
        setve("CodeInterfacePackaging", "Reusable function", false);
        setve("ModelReferenceNumInstancesAllowed", "Multi", false);

        % Only C is supported; C++ is not on the CIGRE DLL ABI roadmap.
        setve("TargetLang", "C", false);

        setve("CompOptLevelCompliant", true, false);
        setve("ModelReferenceCompliant", true, false);

        setve("UseToolchainInfoCompliant", true, false);
        setve("RTWCompilerOptimization", "off", false);
        setve("MakeCommand", "make_rtw", false);

        setve("GenCodeOnly", "off", true);

        setve("RootIOFormat", "Structure reference", false);
    end

    function setve(attribute, value, enab)
        % attribute: configuration parameter name
        % value:     value to assign
        % enab:      false locks the field after setting so the user
        %            cannot change it from the dialog.
        slConfigUISetEnabled(hDlg, hSrc, attribute, true);
        slConfigUISetVal(hDlg, hSrc, attribute, value);
        slConfigUISetEnabled(hDlg, hSrc, attribute, enab);
    end
end
