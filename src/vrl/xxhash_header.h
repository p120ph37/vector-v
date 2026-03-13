// Wrapper declarations for xxhash to avoid namespace conflicts with V's bundled zstd
#ifndef XXHASH_WRAP_H
#define XXHASH_WRAP_H

#include <stdint.h>
#include <stddef.h>

uint32_t xxhash_wrap_32(const void* input, size_t length, uint32_t seed);
uint64_t xxhash_wrap_64(const void* input, size_t length, uint64_t seed);
uint64_t xxhash_wrap_xxh3_64(const void* input, size_t length);
void xxhash_wrap_xxh3_128(const void* input, size_t length, uint64_t* out_hi, uint64_t* out_lo);

#endif
