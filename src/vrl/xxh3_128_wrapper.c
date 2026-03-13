#include <stdint.h>
#include <stddef.h>

// Forward declare xxhash functions from libxxhash
extern uint32_t XXH32(const void* input, size_t length, uint32_t seed);
extern uint64_t XXH64(const void* input, size_t length, uint64_t seed);
extern uint64_t XXH3_64bits(const void* input, size_t length);

typedef struct {
    uint64_t low64;
    uint64_t high64;
} XXH128_hash_t_local;
extern XXH128_hash_t_local XXH3_128bits(const void* input, size_t length);

uint32_t xxhash_wrap_32(const void* input, size_t length, uint32_t seed) {
    return XXH32(input, length, seed);
}

uint64_t xxhash_wrap_64(const void* input, size_t length, uint64_t seed) {
    return XXH64(input, length, seed);
}

uint64_t xxhash_wrap_xxh3_64(const void* input, size_t length) {
    return XXH3_64bits(input, length);
}

void xxhash_wrap_xxh3_128(const void* input, size_t length, uint64_t* out_hi, uint64_t* out_lo) {
    XXH128_hash_t_local h = XXH3_128bits(input, length);
    *out_hi = h.high64;
    *out_lo = h.low64;
}
