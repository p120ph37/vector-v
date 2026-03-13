#!/bin/sh
# Build a thin xxhash wrapper library using the system libxxhash-dev headers.
# The wrapper isolates our bindings from V's bundled zstd XXH_NAMESPACE pollution.
# Requires: libxxhash-dev (apt install libxxhash-dev), gcc (or cc), ar
set -e
cd "$(dirname "$0")"

REBUILD=0
if [ ! -f libxxhash.a ] || [ xxhash_wrapper.c -nt libxxhash.a ] || [ xxhash_wrapper.h -nt libxxhash.a ]; then
    REBUILD=1
fi

if [ "$REBUILD" = "1" ]; then
    ${CC:-cc} -O2 -c xxhash_wrapper.c -o xxhash_wrapper.o
    ar rcs libxxhash.a xxhash_wrapper.o
    rm -f xxhash_wrapper.o
    echo "Built thirdparty/xxhash/libxxhash.a (wrapper only, links against system libxxhash)"
fi
