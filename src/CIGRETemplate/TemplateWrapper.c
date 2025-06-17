#include "<<CigreHeader>>"

#pragma pack(push, 1)

<<InitializeOnly>>

// ----------------------------------------------------------------
__declspec(dllexport) int32_T Model_FirstCall(IEEE_Cigre_DLLInterface_Instance* instance) {
	logout("####################### Model_FirstCall ##############\n");

	if (instance->Time == 0.0) {
		logout("####################### Model_FirstCall Time = 0, doing nothing\n");
	}
	else {
		logout("####################### Model_FirstCall Time > 0, assuming snapshot\n");
		// Get the IO from the instance
		MyModelParameters* parameters = (MyModelParameters*)instance->Parameters;
        <<InputUnpack>>
        <<OutputUnpack>>

		// Restore from heap
        <<RTMVarType>>* <<RTMStructName>> = (<<RTMVarType>>*)heap_get_address(&instance->IntStates[0], 0);
	    <<InternalStatesRestore>> // localDW, rtdw

	   // Copy data back into model
        <<MapInternalStatesToModel>>
        
		// Apply input data
		<<ApplyInputData>>

		// Create a backup of dwork and blockIO
		// malloc is used because bigger dworks will crash due to limited stash size (unless stash size is changed in the compiler)
		<<InternalStatesCache>>

		// Model ref initialise and init
        <<ModelInitialize>>(<<ModelInitialiseInputs>>);

		// restore the old dwork using the backup
        <<InternalStatesRestoreFromCache>>
		
		// Call initialise to set up the memory structure (needs to not zero states) before calling step
		// Rebuild pointers
		<<WrapperName>>_initialize_only(<<ModelInitialiseInputs>>);
        
        // Map any parameters into the model dwork
        <<MapParamsToModel>>

		// Copy the outputs to the instance
        <<ApplyOutputData>>

	}
	logout("####################### Model_FirstCall END ##############\n");
	// Return success
	instance->LastGeneralMessage = ErrorMessage;
	if (instance->LastGeneralMessage[0] != '\0') {
		return IEEE_Cigre_DLLInterface_Return_Message;
	}
	return IEEE_Cigre_DLLInterface_Return_OK;

};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_Initialize(IEEE_Cigre_DLLInterface_Instance* instance) {
	/* 
       Initializes the system by resetting the internal states
	   Arguments: Instance specific model structure containing Inputs, Parameters and Outputs
	   Return:    Integer status 0 (normal), 1 if messages are written, 2 for errors.  See IEEE_Cigre_DLLInterface_types.h
	*/

	logout("####################### Model_Initialize ##############\n");
    MyModelParameters* parameters = (MyModelParameters*)instance->Parameters;

	/*
	// Note that the initial conditions for all models are determined by the main calling program
	// and are passed to this routine via the instance->ExternalOutputs vector.
	// instance->ExternalOutputs is normally the output of this routine, but in the first time step
	// the main program must set the instance->ExternalOutputs to initial values.
    */

    /*
	// All things we need to allocate memory for and store when state is saved
	*/
    
    logout("Initialising heap\n");

    int32_t heapSize = <<heap definition>> + HEAP_HEADER_SIZE + (HEAP_MAX_NR_BUFFERS * 4); // 4 * HEAP_MAX_NR_BUFFERS is max padding
	heap_initialize(&instance->IntStates[0], heapSize);

    logout("Heap initialised. Allocating memory.\n");

    // The following come from the reference model build of the top level model
    // DW_<<ModelName>>_f_T comes from the reference model build of the top level model
    <<RTMVarType>>* <<RTMStructName>> = heap_malloc(&instance->IntStates[0], (int32_t)sizeof(<<RTMVarType>>));
    <<InternalStatesMalloc>>

    // Copy data to a model
    <<MapInternalStatesToModel>>

    // Model ref initialise and init
    <<ModelInitialize>>(<<ModelInitialiseInputs>>);

    // Map any parameters into the model dwork
    <<MapParamsToModel>>

    // Return success
	ErrorMessage[0] = '\0';
    instance->LastGeneralMessage = ErrorMessage;

    logout("####################### Model_Initialize END ##############\n");

	if (instance->LastGeneralMessage[0] != '\0') {
        return IEEE_Cigre_DLLInterface_Return_Message;
    }
    return IEEE_Cigre_DLLInterface_Return_OK;
};

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_Outputs(IEEE_Cigre_DLLInterface_Instance* instance) {
    /* 
       Calculates output equation
       Arguments: Instance specific model structure containing Inputs, Parameters and Outputs
       Return:    Integer status 0 (normal), 1 if messages are written, 2 for errors.  See IEEE_Cigre_DLLInterface_types.h
    */

    // Get the IO from the instance
    MyModelParameters* parameters = (MyModelParameters*)instance->Parameters;
    <<InputUnpack>>
    <<OutputUnpack>>
    
    // Restore from heap
    <<RTMVarType>>* <<RTMStructName>> = (<<RTMVarType>>*)heap_get_address(&instance->IntStates[0], 0);
	<<InternalStatesRestore>> // localDW, rtdw

    // Copy data back into model
    <<MapInternalStatesToModel>>

    // Apply input data
    <<ApplyInputData>>
    
    // Enable parameter update
    <<MapParamsToModel>>
   
    <<ModelStep>>(<<ModelStepInputs>>);

    // Copy the outputs to the instance
    <<ApplyOutputData>>
    
    // Return success
    instance->LastGeneralMessage = ErrorMessage;
	if (instance->LastGeneralMessage[0] != '\0') {
        return IEEE_Cigre_DLLInterface_Return_Message;
    }
    return IEEE_Cigre_DLLInterface_Return_OK;
};
