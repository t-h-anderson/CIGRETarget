/*
 * cigre_read_model_info.c
 *
 * MEX function that reads IEEE/CIGRE DLL model information by loading the
 * DLL directly via Windows LoadLibrary.  This avoids the MATLAB loadlibrary
 * limitations around pointer-to-array struct members (which MATLAB
 * auto-dereferences to the first element, preventing iteration).
 *
 * Usage (MATLAB):
 *   info = cigre_read_model_info(dllPath)
 *
 * Input:
 *   dllPath (char) – absolute path to the CIGRE DLL (.dll)
 *
 * Output:
 *   info (struct) with fields:
 *     Name, Version, Description, GeneralInformation,
 *     ModelCreated, ModelCreator, ModelLastModifiedDate,
 *     ModelLastModifiedBy, ModelModifiedComment, ModelModifiedHistory,
 *     SampleTime   (double, seconds)
 *     EMT_RMS_Mode (double, 1=EMT, 2=RMS, 3=both)
 *     Inputs       (1xN struct array: Name, Description, Unit, DataType, Width)
 *     Outputs      (1xM struct array: Name, Description, Unit, DataType, Width)
 *     Parameters   (1xP struct array: Name, GroupName, Description, Unit,
 *                                     DataType, FixedValue,
 *                                     DefaultValue, MinValue, MaxValue)
 *
 * Build:
 *   mex -outdir <dir> cigre_read_model_info.c -I<CIGRESource>
 *
 * Notes:
 *   - Windows only (uses LoadLibrary / GetProcAddress).
 *   - The DLL is loaded and immediately freed; it does NOT remain resident.
 *   - Parameter union values (DefaultValue / MinValue / MaxValue) are read
 *     as real64_T (the largest scalar member).  The caller re-casts to the
 *     declared DataType if required.
 */

#include "mex.h"
#include "matrix.h"

#ifndef _WIN32
#error "cigre_read_model_info.c is Windows-only (requires LoadLibrary)."
#endif

#include <windows.h>
#include <string.h>
#include "IEEE_Cigre_DLLInterface.h"

/* ------------------------------------------------------------------ */
/* Function-pointer typedef for Model_GetInfo                          */
/* ------------------------------------------------------------------ */
typedef const IEEE_Cigre_DLLInterface_Model_Info* (__cdecl *Model_GetInfo_fp)(void);

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

static mxArray* makeString(const char_T* s)
{
    return mxCreateString((s != NULL) ? s : "");
}

static mxArray* buildSignalArray(
    const IEEE_Cigre_DLLInterface_Signal* sigs, int32_T n)
{
    const char* fields[] = {"Name", "Description", "Unit", "DataType", "Width"};
    mwSize dims[2];
    mxArray* arr;
    int i;

    dims[0] = 1;
    dims[1] = (mwSize)(n > 0 ? n : 0);

    arr = mxCreateStructArray(2, dims, 5, fields);
    if (arr == NULL) return mxCreateStructMatrix(1, 0, 5, fields);

    for (i = 0; i < n; i++) {
        mxSetField(arr, (mwIndex)i, "Name",        makeString(sigs[i].Name));
        mxSetField(arr, (mwIndex)i, "Description", makeString(sigs[i].Description));
        mxSetField(arr, (mwIndex)i, "Unit",        makeString(sigs[i].Unit));
        mxSetField(arr, (mwIndex)i, "DataType",
            mxCreateDoubleScalar((double)sigs[i].DataType));
        mxSetField(arr, (mwIndex)i, "Width",
            mxCreateDoubleScalar((double)sigs[i].Width));
    }
    return arr;
}

static mxArray* buildParameterArray(
    const IEEE_Cigre_DLLInterface_Parameter* params, int32_T n)
{
    const char* fields[] = {
        "Name", "GroupName", "Description", "Unit", "DataType",
        "FixedValue", "DefaultValue", "MinValue", "MaxValue"
    };
    mwSize dims[2];
    mxArray* arr;
    int i;

    dims[0] = 1;
    dims[1] = (mwSize)(n > 0 ? n : 0);

    arr = mxCreateStructArray(2, dims, 9, fields);
    if (arr == NULL) return mxCreateStructMatrix(1, 0, 9, fields);

    for (i = 0; i < n; i++) {
        /* Read union value as real64_T (largest scalar member). */
        double defVal = (double)params[i].DefaultValue.Real64_Val;
        double minVal = (double)params[i].MinValue.Real64_Val;
        double maxVal = (double)params[i].MaxValue.Real64_Val;

        mxSetField(arr, (mwIndex)i, "Name",         makeString(params[i].Name));
        mxSetField(arr, (mwIndex)i, "GroupName",    makeString(params[i].GroupName));
        mxSetField(arr, (mwIndex)i, "Description",  makeString(params[i].Description));
        mxSetField(arr, (mwIndex)i, "Unit",         makeString(params[i].Unit));
        mxSetField(arr, (mwIndex)i, "DataType",
            mxCreateDoubleScalar((double)params[i].DataType));
        mxSetField(arr, (mwIndex)i, "FixedValue",
            mxCreateDoubleScalar((double)params[i].FixedValue));
        mxSetField(arr, (mwIndex)i, "DefaultValue", mxCreateDoubleScalar(defVal));
        mxSetField(arr, (mwIndex)i, "MinValue",     mxCreateDoubleScalar(minVal));
        mxSetField(arr, (mwIndex)i, "MaxValue",     mxCreateDoubleScalar(maxVal));
    }
    return arr;
}

/* ------------------------------------------------------------------ */
/* MEX entry point                                                     */
/* ------------------------------------------------------------------ */
void mexFunction(int nlhs, mxArray* plhs[],
                 int nrhs, const mxArray* prhs[])
{
    char dllPath[MAX_PATH];
    HMODULE hDLL;
    Model_GetInfo_fp pGetInfo;
    const IEEE_Cigre_DLLInterface_Model_Info* info;

    const char* topFields[] = {
        "Name", "Version", "Description", "GeneralInformation",
        "ModelCreated", "ModelCreator",
        "ModelLastModifiedDate", "ModelLastModifiedBy",
        "ModelModifiedComment", "ModelModifiedHistory",
        "SampleTime", "EMT_RMS_Mode",
        "Inputs", "Outputs", "Parameters"
    };
    mxArray* outStruct;

    /* ---- Validate inputs ---- */
    if (nrhs < 1)
        mexErrMsgIdAndTxt("CIGRE:readModelInfo:nargin",
            "One input required: dllPath.");
    if (!mxIsChar(prhs[0]))
        mexErrMsgIdAndTxt("CIGRE:readModelInfo:type",
            "dllPath must be a character array.");

    mxGetString(prhs[0], dllPath, MAX_PATH);

    /* ---- Load DLL ---- */
    hDLL = LoadLibraryA(dllPath);
    if (hDLL == NULL) {
        char msg[512];
        _snprintf_s(msg, sizeof(msg), _TRUNCATE,
            "LoadLibrary failed for '%s' (Windows error %lu).",
            dllPath, (unsigned long)GetLastError());
        mexErrMsgIdAndTxt("CIGRE:readModelInfo:LoadLibrary", msg);
    }

    /* ---- Resolve Model_GetInfo ---- */
    pGetInfo = (Model_GetInfo_fp)GetProcAddress(hDLL, "Model_GetInfo");
    if (pGetInfo == NULL) {
        FreeLibrary(hDLL);
        mexErrMsgIdAndTxt("CIGRE:readModelInfo:GetProcAddress",
            "Model_GetInfo not found in the DLL. "
            "Ensure it is a CIGRE-compliant DLL.");
    }

    /* ---- Call Model_GetInfo ---- */
    info = pGetInfo();
    if (info == NULL) {
        FreeLibrary(hDLL);
        mexErrMsgIdAndTxt("CIGRE:readModelInfo:NullInfo",
            "Model_GetInfo() returned NULL.");
    }

    /* ---- Build output struct ---- */
    outStruct = mxCreateStructMatrix(1, 1, 15, topFields);

    mxSetField(outStruct, 0, "Name",
        makeString(info->ModelName));
    mxSetField(outStruct, 0, "Version",
        makeString(info->ModelVersion));
    mxSetField(outStruct, 0, "Description",
        makeString(info->ModelDescription));
    mxSetField(outStruct, 0, "GeneralInformation",
        makeString(info->GeneralInformation));
    mxSetField(outStruct, 0, "ModelCreated",
        makeString(info->ModelCreated));
    mxSetField(outStruct, 0, "ModelCreator",
        makeString(info->ModelCreator));
    mxSetField(outStruct, 0, "ModelLastModifiedDate",
        makeString(info->ModelLastModifiedDate));
    mxSetField(outStruct, 0, "ModelLastModifiedBy",
        makeString(info->ModelLastModifiedBy));
    mxSetField(outStruct, 0, "ModelModifiedComment",
        makeString(info->ModelModifiedComment));
    mxSetField(outStruct, 0, "ModelModifiedHistory",
        makeString(info->ModelModifiedHistory));
    mxSetField(outStruct, 0, "SampleTime",
        mxCreateDoubleScalar(info->FixedStepBaseSampleTime));
    mxSetField(outStruct, 0, "EMT_RMS_Mode",
        mxCreateDoubleScalar((double)info->EMT_RMS_Mode));

    mxSetField(outStruct, 0, "Inputs",
        buildSignalArray(info->InputPortsInfo,  info->NumInputPorts));
    mxSetField(outStruct, 0, "Outputs",
        buildSignalArray(info->OutputPortsInfo, info->NumOutputPorts));
    mxSetField(outStruct, 0, "Parameters",
        buildParameterArray(info->ParametersInfo, info->NumParameters));

    plhs[0] = outStruct;

    /* ---- Release DLL ---- */
    FreeLibrary(hDLL);
}
