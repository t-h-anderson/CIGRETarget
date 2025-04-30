#include "CIGRE_Defaults.h"

extern IEEE_Cigre_DLLInterface_Model_Info Model_Info;

// ----------------------------------------------------------------
// Subroutines that can be called by the main power system program
// ----------------------------------------------------------------
__declspec(dllexport) const IEEE_Cigre_DLLInterface_Model_Info* __cdecl Model_GetInfo() {
    /* Returns Model Information
    */
    return &Model_Info;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_CheckParameters(IEEE_Cigre_DLLInterface_Instance* instance) {
    /* Checks the parameters on the given range
       Arguments: Instance specific model structure containing Inputs, Parameters and Outputs
       Return:    Integer status 0 (normal), 1 if messages are written, 2 for errors.  See IEEE_Cigre_DLLInterface_types.h
    */
    // Parameter checks done by the program
    // Note - standard min/max checks should be done by the higher level GUI/Program

	printf("Checking parameters...nothing to do!\n");
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T Model_Iterate(IEEE_Cigre_DLLInterface_Instance* instance) {
    //   called in the first time step
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_Terminate(IEEE_Cigre_DLLInterface_Instance* instance) {
    /*   Destroys any objects allocated by the model code - not used
    */

    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_PrintInfo() {
    /* Prints Model Information */

    printf("Cigre/IEEE DLL Standard\n");
    printf("Model name:             %s\n", Model_Info.ModelName);
    printf("Model version:          %s\n", Model_Info.ModelVersion);
    printf("Model description:      %s\n", Model_Info.ModelDescription);
    printf("Model general info:     %s\n", Model_Info.GeneralInformation);
    printf("Model created on:       %s\n", Model_Info.ModelCreated);
    printf("Model created by:       %s\n", Model_Info.ModelCreator);
    printf("Model last modified:    %s\n", Model_Info.ModelLastModifiedDate);
    printf("Model last modified by: %s\n", Model_Info.ModelLastModifiedBy);
    printf("Model modified comment: %s\n", Model_Info.ModelModifiedComment);
    printf("Model modified history: %s\n", Model_Info.ModelModifiedHistory);
    printf("Time Step Sampling Time (sec): %0.5g\n", Model_Info.FixedStepBaseSampleTime);
    switch (Model_Info.EMT_RMS_Mode) {
        case 1:
            printf("EMT/RMS mode:           EMT\n");
            break;
        case 2:
            printf("EMT/RMS mode:           RMS\n");
            break;
        case 3:
            printf("EMT/RMS mode:           EMT and RMS\n");
            break;
        default:
            printf("EMT/RMS mode:           <not available>\n");
    }
    printf("Number of inputs:       %d\n", Model_Info.NumInputPorts);
    printf("Input description:\n");
    for (int k = 0; k < Model_Info.NumInputPorts; k++) {
        printf("  %s\n", Model_Info.InputPortsInfo[k].Name);
    }
    printf("Number of outputs:      %d\n", Model_Info.NumOutputPorts);
    printf("Output description:\n");
    for (int k = 0; k < Model_Info.NumOutputPorts; k++) {
        printf("  %s\n", Model_Info.OutputPortsInfo[k].Name);
    }

    printf("Number of parameters:   %d\n", Model_Info.NumParameters);
    printf("Parameter description:");
    for (int k = 0; k < Model_Info.NumParameters; k++) {
        printf("  %s\n", Model_Info.ParametersInfo[k].Name);
    }

    printf("Number of int    state variables:   %d\n", Model_Info.NumIntStates);
    printf("Number of float  state variables:   %d\n", Model_Info.NumFloatStates);
    printf("Number of double state variables:   %d\n", Model_Info.NumDoubleStates);
    printf("\n");
    fflush(stdout);

    return IEEE_Cigre_DLLInterface_Return_OK;
};