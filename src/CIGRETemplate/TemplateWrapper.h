// ----------------------------------------------------------------------
// Structures defining inputs, outputs, parameters and program structure
// to be called by the DLLImport Tool
// ----------------------------------------------------------------------
#include "IEEE_Cigre_DLLInterface.h"
#include "CIGRE_Defaults.h"
#include "<<WrapperHeader>>"
#include "heap.h"

<<model_reference_types>>

#define NUM_INPUT <<NumInputs>>
#define NUM_OUTPUT <<NumOutputs>>
#define NUM_PARAM <<NumParam>>

/* Macros for accessing real-time model data structure */
#ifndef rtmGetErrorStatus
#define rtmGetErrorStatus(rtm)         ((rtm)->errorStatus)
#endif

#ifndef rtmSetErrorStatus
#define rtmSetErrorStatus(rtm, val)    ((rtm)->errorStatus = (val))
#endif

#ifndef rtmGetErrorStatusPointer
#define rtmGetErrorStatusPointer(rtm)  ((const char **)(&((rtm)->errorStatus)))
#endif

char ErrorMessage[1000];

#if NUM_INPUT > 0
typedef struct _MyModelInputs {
    <<DefineInputs>>
} MyModelInputs;

// Define Input Signals
IEEE_Cigre_DLLInterface_Signal InputSignals[] = {
    // [0] = {
    //     .Name = "In1",                                          // Input Signal name
    //     .Description = "Reference voltage",                     // Description
    //     .Unit = "pu",                                           // Units
    //     .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
    //     .Width = 1                                              // Signal Dimension
    //},
    <<InputDefinition>>
};

#else

// Define Input Signals
IEEE_Cigre_DLLInterface_Signal InputSignals[] = {
     [0] = {
         .Name = "Dummy input",                                  // Input Signal name
         .Description = "No inputs",                             // Description
         .Unit = "pu",                                           // Units
         .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
         .Width = 1                                              // Signal Dimension
    },
};

#endif

#if NUM_OUTPUT > 0

typedef struct _MyModelOutputs {
    <<DefineOutputs>>
} MyModelOutputs;

// Define Output Signals
IEEE_Cigre_DLLInterface_Signal OutputSignals[] = {    
    // [0] = {
    //     .Name = "Out1",                                         // Output machine field voltage
    //     .Description = "Output Field Voltage",                  // Description
    //     .Unit = "pu",                                           // Units
    //     .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
    //     .Width = 1                                              // Array Dimension
    // }
    <<OutputDefinition>>
};

#else

// Define Output Signals
IEEE_Cigre_DLLInterface_Signal OutputSignals[] = {    
     [0] = {
         .Name = "Dummy output",                                 // Output machine field voltage
         .Description = "No outputs",                            // Description
         .Unit = "pu",                                           // Units
         .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
         .Width = 1                                              // Array Dimension
     }
};

#endif

#if NUM_PARAM > 0

typedef struct _MyModelParameters {
	<<DefineParameters>>
} MyModelParameters;

// Define Parameters
IEEE_Cigre_DLLInterface_Parameter Parameters[] = {
	// [0] = {
	//     .Name = "dummy",                                        // Parameter Names
	//     .Description = "A dummy parameter, not used",           // Description
    // 	   .Unit = "sec",                                          // Units
	//     .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
	//     .FixedValue = 0,                                        // 0 for parameters which can be modified at any time, 1 for parameters which need to be defined at T0 but cannot be changed.
	//     .DefaultValue.Real64_Val = 0.1,                         // Default value
	//     .MinValue.Real64_Val = 0.001,                           // Minimum value
	//     .MaxValue.Real64_Val = 100.0                            // Maximum value
    // }
    <<ParameterDefinitions>>
};

#else

typedef void* MyModelParameters;
IEEE_Cigre_DLLInterface_Parameter Parameters[] = {
    [0] = {
        .Name = "dummy",                                        // Parameter Names
        .Description = "A dummy parameter, not used",           // Description
        .Unit = "sec",                                          // Units
        .DataType = IEEE_Cigre_DLLInterface_DataType_real64_T,  // Signal Type
        .FixedValue = 0,                                        // 0 for parameters which can be modified at any time, 1 for parameters which need to be defined at T0 but cannot be changed.
        .DefaultValue.Real64_Val = 0.1,                         // Default value
        .MinValue.Real64_Val = 0.001,                           // Minimum value
        .MaxValue.Real64_Val = 100.0                            // Maximum value
    }
};

#endif

IEEE_Cigre_DLLInterface_Model_Info Model_Info = {
    .DLLInterfaceVersion = { 1, 1, 0, 0 },                              // Release number of the API used during code generation
    .ModelName = "<<ModelName>>",                                       // Model name
    .ModelVersion = "<<ModelVersion>>",                                 // Model version
    .ModelDescription = "<<Description>>",                              // Model description
    .GeneralInformation = "General Information",                        // General information
    .ModelCreated = "<<ModelCreatedDate>>",                             // Model created on
    .ModelCreator = "<<ModelCreatedBy>>",                               // Model created by
    .ModelLastModifiedDate = "<<ModelModifiedOn>>",                     // Model last modified on
    .ModelLastModifiedBy = "<<ModelModifiedBy>>",                       // Model last modified by
    .ModelModifiedComment = "<<ModelModifiedComment>>",                 // Model modified comment
    .ModelModifiedHistory = "<<ModelHistory>>",                         // Model modified history
    .FixedStepBaseSampleTime = <<SampleTime>>,                          // Time Step sampling time (sec)
    .EMT_RMS_Mode = 1,                                                  // Mode: EMT = 1, RMS = 2, EMT & RMS = 3, otherwise: 0
    
    // Inputs
    .NumInputPorts = <<NoInputs>>,                                      // Number of Input Signals
    .InputPortsInfo = InputSignals,                                     // Inputs structure defined above

    // Outputs
    .NumOutputPorts = <<NoOutputs>>,                                    // Number of Output Signals
    .OutputPortsInfo = OutputSignals,                                   // Outputs structure defined above

    // Parameters
    .NumParameters = <<NoParams>>,                                      // Number of Parameters
    .ParametersInfo = Parameters,                                       // Parameters structure defined above

    // Number of State Variables
    .NumIntStates = (<<NumIntStatesNeeded>> + HEAP_HEADER_SIZE + (HEAP_MAX_NR_BUFFERS * 4))/sizeof(int), // Number of Integer states
    .NumFloatStates = 0,                                                // Number of Float states
    .NumDoubleStates = 0                                                // Number of Double states
};
