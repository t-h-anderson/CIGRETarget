#include <windows.h>
#include <inttypes.h>
#include <stdio.h>

#include "IEEE_Cigre_DLLInterface.h"
#include "heap.h"

// ----------------------------------------------------------------
// Subroutines that can be called by the main power system program
// ----------------------------------------------------------------
__declspec(dllexport) const IEEE_Cigre_DLLInterface_Model_Info* __cdecl Model_GetInfo() ;

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_CheckParameters(IEEE_Cigre_DLLInterface_Instance* instance);

// ----------------------------------------------------------------
__declspec(dllexport) int32_T __cdecl Model_PrintInfo();

// ----------------------------------------------------------------
__declspec(dllexport) int32_T Model_Iterate(IEEE_Cigre_DLLInterface_Instance* instance);