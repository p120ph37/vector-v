// Wrapper header for xxhash that avoids namespace conflicts with V's bundled
// zstd (which redefines xxhash symbols via XXH_NAMESPACE=XXH_INLINE_).
//
// This header declares wrapper functions with unique names that delegate to
// the real xxhash API in libxxhash.a. The implementation is in xxhash_wrapper.c.
#ifndef VECTORV_XXHASH_WRAPPER_H
#define VECTORV_XXHASH_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint64_t low64;
    uint64_t high64;
} vectorv_xxh128_hash_t;

uint32_t vectorv_xxh32(const void* input, size_t length, uint32_t seed);
uint64_t vectorv_xxh64(const void* input, size_t length, uint64_t seed);
uint64_t vectorv_xxh3_64bits(const void* input, size_t length);
vectorv_xxh128_hash_t vectorv_xxh3_128bits(const void* input, size_t length);

#endif
