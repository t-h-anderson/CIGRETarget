#ifndef _CIGRE_HEAP_
#define _CIGRE_HEAP_

#include <windows.h>
#include <stdint.h>
#include <stdio.h>

#define HEAP_MAX_NR_BUFFERS 10
#define HEAP_HEADER_SIZE (12+8+(HEAP_MAX_NR_BUFFERS*8))

extern void heap_print(void *heap_base);
extern void heap_initialize(void *heap_base, int32_t max_size);
extern void *heap_malloc(void *heap_base, int32_t buf_size);
extern void * heap_get_address(void *heap_base, int32_t elem);

#endif /* _CIGRE_HEAP_*/