function cigre_callback_handler( hDlg, hSrc, action )
% cigre_callback_handler
% Group all settings for target into one place. Set default options for
% target, and limit user changes.

% Copyright 2024 The MathWorks, Inc.
% $Revision: 1 $  $Date: 2017-02-01 10:25:34 +0000 (Wed, 01 Feb 2017) $


switch action
    case 'select'
        %Apply Settings when cigre target selected.
        general_settings;
        
    case 'activate'
        %Do nothing - Will probably need to add calls here when we add new
        %options specifically for this app
        
        general_settings;
    case 'postapply'
        %Do nothing - Will probably need to add calls here when we add new
        %options specifically for this app
        
    otherwise
        error('Unknown action >%s<.\n', action);
end
        


% ==========================================================
    function general_settings
        %NOTE: Some care needs to be taken about order of the below
        %parameters. I.e. SolverType should come before Solver, as this
        %affects the allowed list (and the default is variable-step which
        %isn't compatible with FixedStepDiscrete
                
        %See Configuration Parameter Reference under Real-Time Workshop in
        %the Matlab help for some descriptions of the following options.
        
        %Basic solver settings
        setve('SolverType','Fixed-step',false);
        setve('SolverName','FixedStepDiscrete',false);

        % Outputs - for testing 
        %setve('SaveTime', true, fase);
        %setve('SaveOutput', true, fase);

        % Hardware - default is 64 bit. Can change this to 32-bit manually
        setve('ProdHWDeviceType', 'x86-64 (Windows64)',true);
        
        % Code Generation
        % setve('GenCodeOnly', true, false);

        setve('ZeroInternalMemoryAtStartup', false, false)
        setve('ZeroExternalMemoryAtStartup', false, false)
        
        % Avoid warning on max id lenght
        % 31 is a limit for PSCAD, not for CIGRE so we fix this in the wrapper
        % setve('MaxIdLength', 31, true)
        setve('ModelReferenceSymbolNameMessage', 'none', true)

        %Force CodeInfo to be generated.
        %This is the default in newer versions of RTW
        setve('GenerateCodeInfo','on',true);
        
        % Needs to be reusable
        setve('CodeInterfacePackaging','Reusable function',false);
               
        %Code generation options
        setve('TargetLang', 'C', false); % Only supporting C code at the moment
        
        setve('CompOptLevelCompliant', true, false);
        setve('ModelReferenceCompliant',true,false);
        
        % Toolchain support
        setve('UseToolchainInfoCompliant', true, false);
        setve('RTWCompilerOptimization','off', false);
        setve('MakeCommand','make_rtw', false);
        
        % DLL toolchain
        setve('GenCodeOnly','off', true);

        setve('RootIOFormat', 'Structure reference', false);

        % TODO: May stop some issues with custom storage classes
        %setve('IgnoreCustomStorageClasses','on', true);
        
 
                
    end

% ==========================================================
    function setve(attribute, value, enab)
        %Helper function used to simplify setting any Configuration
        %parameter.
        %Pass the name of the attribute, the required value and also a flag
        %to indicate whether the setting should be locked or not - thereby
        %preventing the user changing it.
        slConfigUISetEnabled(hDlg, hSrc, attribute, true);
        slConfigUISetVal(hDlg, hSrc, attribute, value);
        slConfigUISetEnabled(hDlg, hSrc, attribute, enab);
    end
end