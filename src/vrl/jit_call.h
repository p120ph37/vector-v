// jit_call.h - Helper to invoke a JIT-compiled VRL function via void pointer.
// This avoids V's limitation of not being able to cast voidptr to fn types directly.

#ifndef JIT_CALL_H
#define JIT_CALL_H

typedef int (*jit_eval_fn_t)(const char *in_json, int in_len, char *out_json, int out_cap);

static inline int jit_call_eval(void *fn_ptr, const char *in_json, int in_len, char *out_json, int out_cap) {
    return ((jit_eval_fn_t)fn_ptr)(in_json, in_len, out_json, out_cap);
}

#endif
