#include "CIGRE_Defaults.h"
#include "IEEE_Cigre_DLLInterface.h"

#define DEBUG 1

// CIGRE_Defaults
void logout(char *str){
    if (DEBUG) {
        printf(str);
        fflush(stdout);
    }
};

// IEEE_Cigre_DLLInterface
extern IEEE_Cigre_DLLInterface_Model_Info Model_Info;

__declspec(dllexport) const IEEE_Cigre_DLLInterface_Model_Info* __cdecl Model_GetInfo() {
    /* Function pointer types used when DLL is loaded explicitly via LoadLibrary */
    return &Model_Info;
};

// ----------------------------------------------------------------
// Subroutines that can be called by the main power system program
// ----------------------------------------------------------------
// Functions below return a integer value:
//     return 0 - fine
//     return 1 - general message (see LastGeneralMessage)
//     return 2 - error message and terminate (see LastErrorMessage)
 
__declspec(dllexport) int32_T __cdecl Model_CheckParameters(IEEE_Cigre_DLLInterface_Instance* instance) {
    /* Checks the parameters
       Arguments: Instance specific model structure containing Inputs, Parameters and Outputs
       Return:    Integer status 0 (normal), 1 if messages are written, 2 for errors.  See IEEE_Cigre_DLLInterface_types.h
    */
    // Model_CheckParameters is called in the first step of a simulation (so model writers can perform
    // more complex checks on input parameters in addition to simple min/max checks).

	printf("Checking parameters...nothing to do!\n");
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T Model_Iterate(IEEE_Cigre_DLLInterface_Instance* instance) {
    // Model_Iterate is only called for RMS programs, N times after Model_Outputs is called.
    // It can be used for RMS programs to approximate fast control action (such as fault behaviour) which cannot directly
    // be simulated with large time step RMS programs.
    // The model code should also update/store its state variables at the end of this call before returning.
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_Terminate(IEEE_Cigre_DLLInterface_Instance* instance) {
    // Called by the main simulation program at the end of a simulation (or in the event the simulation is terminated).
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_PrintInfo() {
    // Called in the first step of a simulation to allow model writers to write general model info to the main simulation.

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