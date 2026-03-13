#!/bin/sh
# Build static xxhash library from the single-header implementation
# plus a thin wrapper to isolate from V's bundled zstd namespace.
# Requires: gcc (or cc), ar
set -e
cd "$(dirname "$0")"

REBUILD=0
for src in xxhash_impl.c xxhash_wrapper.c; do
    if [ ! -f libxxhash.a ] || [ "$src" -nt libxxhash.a ] || [ xxhash.h -nt libxxhash.a ]; then
        REBUILD=1
        break
    fi
done

if [ "$REBUILD" = "1" ]; then
    ${CC:-cc} -O2 -c xxhash_impl.c -o xxhash_impl.o
    ${CC:-cc} -O2 -c xxhash_wrapper.c -o xxhash_wrapper.o
    ar rcs libxxhash.a xxhash_impl.o xxhash_wrapper.o
    rm -f xxhash_impl.o xxhash_wrapper.o
    echo "Built thirdparty/xxhash/libxxhash.a"
fi
