// Compile xxhash as a static library from the single-header implementation.
// See https://github.com/Cyan4973/xxHash for details.
//
// XXH_STATIC_LINKING_ONLY exposes full struct definitions needed for compilation.
// XXH_IMPLEMENTATION enables the implementation section of the header.
#define XXH_STATIC_LINKING_ONLY
#define XXH_IMPLEMENTATION
#include "xxhash.h"
