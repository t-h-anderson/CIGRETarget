#ifndef _CIGRE_HEAP_
#define _CIGRE_HEAP_

#include <windows.h>
#include <stdint.h>
#include <stdio.h>

#define HEAP_MAX_NR_BUFFERS 10

#pragma warning(push)
#pragma warning(disable: 4200) /* C99 flexible array member - valid but nonstandard in MSVC */
typedef struct Heap_ {
	int32_t max_size;
	int32_t nr_allocated_buffers;
	int32_t allocated_size;
	uint8_t *next_free_buf_start;
	uint64_t buffer_pointers[HEAP_MAX_NR_BUFFERS];
	uint8_t start_buffer[];
} Heap;
#pragma warning(pop)

/* Actual byte size of the heap header. Using sizeof(Heap) keeps this
 * correct across architectures: the struct picks up whatever padding the
 * compiler inserts (104 bytes on 64-bit MSVC, not the 100 a manual field
 * count gave), so the heap bounds accounting can never under-count. */
#define HEAP_HEADER_SIZE (sizeof(Heap))

extern void heap_print(void *heap_base);
extern void heap_initialize(void *heap_base, int32_t max_size);
extern void *heap_malloc(void *heap_base, int32_t buf_size);
extern void * heap_get_address(void *heap_base, int32_t elem);

#endif /* _CIGRE_HEAP_*/