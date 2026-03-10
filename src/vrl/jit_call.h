// jit_call.h - Helpers to invoke JIT-compiled VRL functions via void pointers.
// This avoids V's limitation of not being able to cast voidptr to fn types directly.

#ifndef JIT_CALL_H
#define JIT_CALL_H

#include <stdint.h>

// Legacy JSON-based interface
typedef int (*jit_eval_fn_t)(const char *in_json, int in_len, char *out_json, int out_cap);

static inline int jit_call_eval(void *fn_ptr, const char *in_json, int in_len, char *out_json, int out_cap) {
    return ((jit_eval_fn_t)fn_ptr)(in_json, in_len, out_json, out_cap);
}

// Direct interface — bypasses JSON serialization entirely.
// These call functions in the JIT-compiled code that operate on a global Val context.
typedef void (*jit_void_fn)(void);
typedef void (*jit_set_str_fn)(const char*, const char*, int);
typedef void (*jit_set_int_fn)(const char*, int64_t);
typedef void (*jit_set_float_fn)(const char*, double);
typedef void (*jit_set_bool_fn)(const char*, int);
typedef int (*jit_int_fn)(void);
typedef const char* (*jit_key_fn)(int);
typedef int (*jit_iget_fn)(int);
typedef const char* (*jit_sget_fn)(int);
typedef int64_t (*jit_i64get_fn)(int);
typedef double (*jit_fget_fn)(int);
typedef int (*jit_json_fn)(int, char*, int);

static inline void jit_call_init(void *fp) { ((jit_void_fn)fp)(); }
static inline void jit_call_set_str(void *fp, const char *k, const char *v, int vl) { ((jit_set_str_fn)fp)(k, v, vl); }
static inline void jit_call_set_int(void *fp, const char *k, int64_t v) { ((jit_set_int_fn)fp)(k, v); }
static inline void jit_call_set_float(void *fp, const char *k, double v) { ((jit_set_float_fn)fp)(k, v); }
static inline void jit_call_set_bool(void *fp, const char *k, int v) { ((jit_set_bool_fn)fp)(k, v); }
static inline int jit_call_eval_direct(void *fp) { return ((jit_int_fn)fp)(); }
static inline int jit_call_result_len(void *fp) { return ((jit_int_fn)fp)(); }
static inline const char* jit_call_result_key(void *fp, int i) { return ((jit_key_fn)fp)(i); }
static inline int jit_call_result_type(void *fp, int i) { return ((jit_iget_fn)fp)(i); }
static inline const char* jit_call_result_str_ptr(void *fp, int i) { return ((jit_sget_fn)fp)(i); }
static inline int jit_call_result_str_len(void *fp, int i) { return ((jit_iget_fn)fp)(i); }
static inline int64_t jit_call_result_int_val(void *fp, int i) { return ((jit_i64get_fn)fp)(i); }
static inline double jit_call_result_float_val(void *fp, int i) { return ((jit_fget_fn)fp)(i); }
static inline int jit_call_result_bool_val(void *fp, int i) { return ((jit_iget_fn)fp)(i); }
static inline int jit_call_result_json(void *fp, int i, char *buf, int cap) { return ((jit_json_fn)fp)(i, buf, cap); }

#endif
