
#include "heap.h"

typedef struct Heap_ {
	int32_t max_size;                       
	int32_t nr_allocated_buffers;               
	int32_t allocated_size;                     
	uint8_t *next_fee_buf_start;                    
	uint64_t buffer_pointers[HEAP_MAX_NR_BUFFERS];
	uint8_t start_buffer[];
} Heap;

void heap_print(void *heap_base)
{
	Heap *heap = (Heap *)heap_base;
	int idx;

	printf("======= HEAP =======\n");
	printf("max_size:%d\n", heap->max_size);
	printf("nr_allocated_buffers:%d\n", heap->nr_allocated_buffers);
	printf("allocated_size:%d\n", heap->allocated_size);
	printf("next_free_buf_start:0x%llX\n", (uint64_t)heap->next_fee_buf_start);
	for (idx = 0;idx < HEAP_MAX_NR_BUFFERS;idx++) 
	{
		printf("buffer_pointer[%d]:%lld\n", idx, heap->buffer_pointers[idx]);
	}
	printf("start_buffer:0x%llX\n", (uint64_t)heap->start_buffer);
	printf("===== END HEAP =====\n");
}

void heap_initialize(void *heap_base, int32_t max_size)
{
	Heap *heap = (Heap *)heap_base;
	int idx;

	// FIXME: Zero heap memory (as no zero initialization in models)
	memset(heap_base, 0, max_size);

	heap->max_size = max_size;
	heap->nr_allocated_buffers = 0;
	heap->allocated_size = HEAP_HEADER_SIZE;
	heap->next_fee_buf_start = &heap->start_buffer[0];
	for (idx = 0; idx < HEAP_MAX_NR_BUFFERS; idx++) {
	    heap->buffer_pointers[idx] = 0; 
    }
}

void *heap_malloc(void *heap_base, int32_t buf_size) {

	Heap *heap = (Heap *)heap_base;
	void *return_addr;
	int32_t rem;
	uint64_t b, n;

	/* Ensure 4 byte alignment (Needed?)
	 * FIXME: set it to 8 is safer
	 */
	rem = buf_size % 4;
	if (rem != 0) {
		buf_size = buf_size + (4 - rem);
	}

	/* First check 
	 */
	if (heap->nr_allocated_buffers >= HEAP_MAX_NR_BUFFERS) {
		/* No more buffers*/
		printf("*** ERROR: No more buffers\n");
		return NULL;
	}
	if ((heap->allocated_size + buf_size) > heap->max_size) {
		/* Not enough memory*/
		printf("*** ERROR: Not enough memory\n");
		return NULL;
	}

	heap->allocated_size = heap->allocated_size + buf_size;
	return_addr = heap->next_fee_buf_start;

	n = (uint64_t)heap->next_fee_buf_start;
	b = (uint64_t)heap_base;
	heap->buffer_pointers[heap->nr_allocated_buffers] = n-b;
	heap->next_fee_buf_start = heap->next_fee_buf_start + buf_size;
	heap->nr_allocated_buffers = heap->nr_allocated_buffers + 1;

	return return_addr;
}

void * heap_get_address(void *heap_base, int32_t elem)
{
	Heap *heap = (Heap *)heap_base;
	uint64_t b, n;

	if (elem >= heap->nr_allocated_buffers) {
		printf("*** ERROR: Trying to get address for unallocated buffer.\n");
		return NULL;
	}
	n = heap->buffer_pointers[elem];
	b = (uint64_t)heap_base;

	return (void*)(b + n);
}

