#include <windows.h>
#include <inttypes.h>
#include <stdio.h>

void logout(char *str);

/* Abort Model_Initialize with a CIGRE error if a heap allocation failed.
 * heap_malloc returns NULL when the model state does not fit the
 * IntStates buffer (or HEAP_MAX_NR_BUFFERS is exceeded). Without this
 * check the generated code dereferences NULL and crashes the host
 * simulator instead of reporting a recoverable error. Expands inside
 * Model_Initialize, which returns int32_T. */
#define CIGRE_REQUIRE_ALLOC(ptr, instance)                                  \
    do {                                                                    \
        if ((ptr) == NULL) {                                                \
            (instance)->LastErrorMessage =                                  \
                "CIGRE DLL: heap allocation failed - model state does "     \
                "not fit the IntStates buffer.";                            \
            return IEEE_Cigre_DLLInterface_Return_Error;                    \
        }                                                                   \
    } while (0)