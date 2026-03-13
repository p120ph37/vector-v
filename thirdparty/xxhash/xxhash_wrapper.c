// Wrapper implementation that includes the system xxhash.h and delegates.
// Compiled into a small static lib to isolate our code from V's bundled
// zstd XXH_NAMESPACE pollution.
// Requires: libxxhash-dev (apt install libxxhash-dev)
#define XXH_STATIC_LINKING_ONLY
#include <xxhash.h>
#include "xxhash_wrapper.h"

uint32_t vectorv_xxh32(const void* input, size_t length, uint32_t seed) {
    return XXH32(input, length, seed);
}

uint64_t vectorv_xxh64(const void* input, size_t length, uint64_t seed) {
    return XXH64(input, length, seed);
}

uint64_t vectorv_xxh3_64bits(const void* input, size_t length) {
    return XXH3_64bits(input, length);
}

vectorv_xxh128_hash_t vectorv_xxh3_128bits(const void* input, size_t length) {
    XXH128_hash_t h = XXH3_128bits(input, length);
    vectorv_xxh128_hash_t result;
    result.low64 = h.low64;
    result.high64 = h.high64;
    return result;
}
