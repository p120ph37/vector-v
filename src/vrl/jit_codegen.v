module vrl

import strings

// JIT C runtime preamble - embedded C code that provides the value type,
// arena allocator, arithmetic, string operations, JSON parsing/serialization,
// and stdlib function implementations for JIT-compiled VRL programs.
const jit_c_preamble = '
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

/* ---- Arena allocator ---- */
#define JIT_ARENA_SIZE (256 * 1024)
static char jit_arena[JIT_ARENA_SIZE];
static size_t jit_arena_pos = 0;

static void *jit_alloc(size_t sz) {
    sz = (sz + 7) & ~7;
    if (jit_arena_pos + sz > JIT_ARENA_SIZE) return NULL;
    void *p = jit_arena + jit_arena_pos;
    jit_arena_pos += sz;
    memset(p, 0, sz);
    return p;
}
static void jit_arena_reset(void) { jit_arena_pos = 0; }

/* ---- Tagged union value type ---- */
enum { VT_NULL=0, VT_BOOL=1, VT_INT=2, VT_FLOAT=3, VT_STRING=4, VT_ARRAY=5, VT_OBJECT=6 };

typedef struct Val {
    int type;
    union {
        int64_t i;
        double f;
        int b;
        struct { char *p; int n; } s;
        struct { struct Val *items; int len; int cap; } a;
        struct { char **keys; struct Val *vals; int len; int cap; } o;
    } u;
} Val;

/* ---- Constructors ---- */
static Val vn(void) { Val v; memset(&v, 0, sizeof(v)); return v; }
static Val vb(int b) { Val v; memset(&v, 0, sizeof(v)); v.type = VT_BOOL; v.u.b = b; return v; }
static Val vi(int64_t i) { Val v; memset(&v, 0, sizeof(v)); v.type = VT_INT; v.u.i = i; return v; }
static Val vf(double f) { Val v; memset(&v, 0, sizeof(v)); v.type = VT_FLOAT; v.u.f = f; return v; }

static Val vs(const char *s, int n) {
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING;
    v.u.s.p = (char *)jit_alloc(n + 1);
    if (v.u.s.p) { memcpy(v.u.s.p, s, n); v.u.s.p[n] = 0; }
    v.u.s.n = n;
    return v;
}
static Val vsl(const char *s) { return vs(s, (int)strlen(s)); }

/* ---- Array ---- */
static Val va_new(void) {
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_ARRAY;
    v.u.a.cap = 16;
    v.u.a.items = (Val *)jit_alloc(16 * sizeof(Val));
    return v;
}
static void va_push(Val *a, Val item) {
    if (a->type != VT_ARRAY) return;
    if (a->u.a.len >= a->u.a.cap) {
        int nc = a->u.a.cap * 2;
        Val *ni = (Val *)jit_alloc(nc * sizeof(Val));
        if (!ni) return;
        memcpy(ni, a->u.a.items, a->u.a.len * sizeof(Val));
        a->u.a.items = ni;
        a->u.a.cap = nc;
    }
    a->u.a.items[a->u.a.len++] = item;
}

/* ---- Object ---- */
static Val vo_new(void) {
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_OBJECT;
    v.u.o.cap = 16;
    v.u.o.keys = (char **)jit_alloc(16 * sizeof(char*));
    v.u.o.vals = (Val *)jit_alloc(16 * sizeof(Val));
    return v;
}
static Val vo_get(Val o, const char *k) {
    if (o.type != VT_OBJECT) return vn();
    for (int i = 0; i < o.u.o.len; i++)
        if (strcmp(o.u.o.keys[i], k) == 0) return o.u.o.vals[i];
    return vn();
}
static void vo_set(Val *o, const char *k, Val v) {
    if (o->type != VT_OBJECT) return;
    for (int i = 0; i < o->u.o.len; i++) {
        if (strcmp(o->u.o.keys[i], k) == 0) { o->u.o.vals[i] = v; return; }
    }
    if (o->u.o.len >= o->u.o.cap) {
        int nc = o->u.o.cap * 2;
        char **nk = (char **)jit_alloc(nc * sizeof(char*));
        Val *nv = (Val *)jit_alloc(nc * sizeof(Val));
        if (!nk || !nv) return;
        memcpy(nk, o->u.o.keys, o->u.o.len * sizeof(char*));
        memcpy(nv, o->u.o.vals, o->u.o.len * sizeof(Val));
        o->u.o.keys = nk; o->u.o.vals = nv; o->u.o.cap = nc;
    }
    int n = (int)strlen(k);
    o->u.o.keys[o->u.o.len] = (char *)jit_alloc(n + 1);
    if (o->u.o.keys[o->u.o.len]) memcpy(o->u.o.keys[o->u.o.len], k, n + 1);
    o->u.o.vals[o->u.o.len] = v;
    o->u.o.len++;
}
static void vo_del(Val *o, const char *k) {
    if (o->type != VT_OBJECT) return;
    for (int i = 0; i < o->u.o.len; i++) {
        if (strcmp(o->u.o.keys[i], k) == 0) {
            for (int j = i; j < o->u.o.len - 1; j++) {
                o->u.o.keys[j] = o->u.o.keys[j+1];
                o->u.o.vals[j] = o->u.o.vals[j+1];
            }
            o->u.o.len--;
            return;
        }
    }
}
static void vo_merge(Val *dst, Val src) {
    if (dst->type != VT_OBJECT || src.type != VT_OBJECT) return;
    for (int i = 0; i < src.u.o.len; i++)
        vo_set(dst, src.u.o.keys[i], src.u.o.vals[i]);
}

/* ---- Truthiness ---- */
static int truthy(Val v) {
    switch (v.type) {
        case VT_BOOL: return v.u.b;
        case VT_NULL: return 0;
        case VT_STRING: return v.u.s.n > 0;
        case VT_INT: return v.u.i != 0;
        case VT_FLOAT: return v.u.f != 0.0;
        default: return 1;
    }
}

/* ---- Equality ---- */
static int json_serialize(Val v, char *buf, int cap);
static int val_eq(Val a, Val b) {
    if (a.type != b.type) {
        if (a.type == VT_INT && b.type == VT_FLOAT) return (double)a.u.i == b.u.f;
        if (a.type == VT_FLOAT && b.type == VT_INT) return a.u.f == (double)b.u.i;
        return 0;
    }
    switch (a.type) {
        case VT_NULL: return 1;
        case VT_BOOL: return a.u.b == b.u.b;
        case VT_INT: return a.u.i == b.u.i;
        case VT_FLOAT: return a.u.f == b.u.f;
        case VT_STRING: return a.u.s.n == b.u.s.n && memcmp(a.u.s.p, b.u.s.p, a.u.s.n) == 0;
        default: {
            char ba[4096], bb[4096];
            int na = json_serialize(a, ba, sizeof(ba));
            int nb = json_serialize(b, bb, sizeof(bb));
            return na == nb && memcmp(ba, bb, na) == 0;
        }
    }
}

/* ---- Arithmetic ---- */
static Val val_add(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) return vi(a.u.i + b.u.i);
    if (a.type == VT_FLOAT && b.type == VT_FLOAT) return vf(a.u.f + b.u.f);
    if (a.type == VT_INT && b.type == VT_FLOAT) return vf((double)a.u.i + b.u.f);
    if (a.type == VT_FLOAT && b.type == VT_INT) return vf(a.u.f + (double)b.u.i);
    if (a.type == VT_STRING && b.type == VT_STRING) {
        int n = a.u.s.n + b.u.s.n;
        char *p = (char *)jit_alloc(n + 1);
        if (p) { memcpy(p, a.u.s.p, a.u.s.n); memcpy(p + a.u.s.n, b.u.s.p, b.u.s.n); p[n] = 0; }
        Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = p; v.u.s.n = n; return v;
    }
    return vn();
}
static Val val_sub(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) return vi(a.u.i - b.u.i);
    if (a.type == VT_FLOAT && b.type == VT_FLOAT) return vf(a.u.f - b.u.f);
    if (a.type == VT_INT && b.type == VT_FLOAT) return vf((double)a.u.i - b.u.f);
    if (a.type == VT_FLOAT && b.type == VT_INT) return vf(a.u.f - (double)b.u.i);
    return vn();
}
static Val val_mul(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) return vi(a.u.i * b.u.i);
    if (a.type == VT_FLOAT && b.type == VT_FLOAT) return vf(a.u.f * b.u.f);
    if (a.type == VT_INT && b.type == VT_FLOAT) return vf((double)a.u.i * b.u.f);
    if (a.type == VT_FLOAT && b.type == VT_INT) return vf(a.u.f * (double)b.u.i);
    return vn();
}
static Val val_div(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) { if (b.u.i == 0) return vn(); return vi(a.u.i / b.u.i); }
    if (a.type == VT_FLOAT && b.type == VT_FLOAT) { if (b.u.f == 0.0) return vn(); return vf(a.u.f / b.u.f); }
    if (a.type == VT_INT && b.type == VT_FLOAT) { if (b.u.f == 0.0) return vn(); return vf((double)a.u.i / b.u.f); }
    if (a.type == VT_FLOAT && b.type == VT_INT) { if (b.u.i == 0) return vn(); return vf(a.u.f / (double)b.u.i); }
    return vn();
}
static Val val_mod(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) { if (b.u.i == 0) return vn(); return vi(a.u.i % b.u.i); }
    return vn();
}
static Val val_neg(Val a) {
    if (a.type == VT_INT) return vi(-a.u.i);
    if (a.type == VT_FLOAT) return vf(-a.u.f);
    return vn();
}

/* ---- Comparison ---- */
static Val val_lt(Val a, Val b) {
    if (a.type == VT_INT && b.type == VT_INT) return vb(a.u.i < b.u.i);
    if (a.type == VT_FLOAT && b.type == VT_FLOAT) return vb(a.u.f < b.u.f);
    if (a.type == VT_INT && b.type == VT_FLOAT) return vb((double)a.u.i < b.u.f);
    if (a.type == VT_FLOAT && b.type == VT_INT) return vb(a.u.f < (double)b.u.i);
    if (a.type == VT_STRING && b.type == VT_STRING) {
        int c = memcmp(a.u.s.p, b.u.s.p, a.u.s.n < b.u.s.n ? a.u.s.n : b.u.s.n);
        return vb(c < 0 || (c == 0 && a.u.s.n < b.u.s.n));
    }
    return vn();
}
static Val val_gt(Val a, Val b) { return val_lt(b, a); }
static Val val_le(Val a, Val b) {
    Val r = val_lt(a, b);
    if (r.type == VT_BOOL && r.u.b) return r;
    return vb(val_eq(a, b));
}
static Val val_ge(Val a, Val b) { return val_le(b, a); }

/* ---- String functions ---- */
static Val fn_downcase(Val a) {
    if (a.type != VT_STRING) return vn();
    char *p = (char *)jit_alloc(a.u.s.n + 1);
    if (!p) return vn();
    for (int i = 0; i < a.u.s.n; i++) p[i] = (char)tolower((unsigned char)a.u.s.p[i]);
    p[a.u.s.n] = 0;
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = p; v.u.s.n = a.u.s.n; return v;
}
static Val fn_upcase(Val a) {
    if (a.type != VT_STRING) return vn();
    char *p = (char *)jit_alloc(a.u.s.n + 1);
    if (!p) return vn();
    for (int i = 0; i < a.u.s.n; i++) p[i] = (char)toupper((unsigned char)a.u.s.p[i]);
    p[a.u.s.n] = 0;
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = p; v.u.s.n = a.u.s.n; return v;
}
static Val fn_contains(Val a, Val b) {
    if (a.type != VT_STRING || b.type != VT_STRING) return vb(0);
    if (b.u.s.n == 0) return vb(1);
    if (b.u.s.n > a.u.s.n) return vb(0);
    return vb(strstr(a.u.s.p, b.u.s.p) != NULL);
}
static Val fn_starts_with(Val a, Val b) {
    if (a.type != VT_STRING || b.type != VT_STRING) return vb(0);
    if (b.u.s.n > a.u.s.n) return vb(0);
    return vb(memcmp(a.u.s.p, b.u.s.p, b.u.s.n) == 0);
}
static Val fn_ends_with(Val a, Val b) {
    if (a.type != VT_STRING || b.type != VT_STRING) return vb(0);
    if (b.u.s.n > a.u.s.n) return vb(0);
    return vb(memcmp(a.u.s.p + a.u.s.n - b.u.s.n, b.u.s.p, b.u.s.n) == 0);
}
static Val fn_length(Val a) {
    switch (a.type) {
        case VT_STRING: return vi(a.u.s.n);
        case VT_ARRAY: return vi(a.u.a.len);
        case VT_OBJECT: return vi(a.u.o.len);
        default: return vi(0);
    }
}
static Val fn_strip_whitespace(Val a) {
    if (a.type != VT_STRING) return vn();
    int start = 0, end = a.u.s.n;
    while (start < end && isspace((unsigned char)a.u.s.p[start])) start++;
    while (end > start && isspace((unsigned char)a.u.s.p[end-1])) end--;
    return vs(a.u.s.p + start, end - start);
}
static Val fn_replace(Val s, Val pat, Val rep) {
    if (s.type != VT_STRING || pat.type != VT_STRING || rep.type != VT_STRING) return vn();
    if (pat.u.s.n == 0) return s;
    int count = 0;
    char *p = s.u.s.p;
    while ((p = strstr(p, pat.u.s.p)) != NULL) { count++; p += pat.u.s.n; }
    if (count == 0) return s;
    int new_len = s.u.s.n + count * (rep.u.s.n - pat.u.s.n);
    char *result = (char *)jit_alloc(new_len + 1);
    if (!result) return s;
    char *dst = result;
    p = s.u.s.p;
    while (*p) {
        if (strncmp(p, pat.u.s.p, pat.u.s.n) == 0) {
            memcpy(dst, rep.u.s.p, rep.u.s.n); dst += rep.u.s.n; p += pat.u.s.n;
        } else { *dst++ = *p++; }
    }
    *dst = 0;
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = result; v.u.s.n = new_len; return v;
}
static Val fn_split(Val s, Val delim) {
    if (s.type != VT_STRING || delim.type != VT_STRING) return vn();
    Val arr = va_new();
    if (delim.u.s.n == 0) { va_push(&arr, s); return arr; }
    char *p = s.u.s.p, *end = s.u.s.p + s.u.s.n;
    while (p <= end) {
        char *found = strstr(p, delim.u.s.p);
        if (!found || found >= end) { va_push(&arr, vs(p, (int)(end - p))); break; }
        va_push(&arr, vs(p, (int)(found - p)));
        p = found + delim.u.s.n;
    }
    return arr;
}
static Val fn_join(Val arr, Val sep) {
    if (arr.type != VT_ARRAY || arr.u.a.len == 0) return vsl("");
    int total = 0;
    for (int i = 0; i < arr.u.a.len; i++) {
        Val item = arr.u.a.items[i];
        if (item.type == VT_STRING) total += item.u.s.n;
        else { char b[64]; total += snprintf(b, sizeof(b), "%lld", (long long)item.u.i); }
        if (i > 0 && sep.type == VT_STRING) total += sep.u.s.n;
    }
    char *result = (char *)jit_alloc(total + 1);
    if (!result) return vsl("");
    char *dst = result;
    for (int i = 0; i < arr.u.a.len; i++) {
        if (i > 0 && sep.type == VT_STRING) { memcpy(dst, sep.u.s.p, sep.u.s.n); dst += sep.u.s.n; }
        Val item = arr.u.a.items[i];
        if (item.type == VT_STRING) { memcpy(dst, item.u.s.p, item.u.s.n); dst += item.u.s.n; }
        else { dst += sprintf(dst, "%lld", (long long)item.u.i); }
    }
    *dst = 0;
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = result; v.u.s.n = (int)(dst - result); return v;
}

/* ---- Type conversion ---- */
static Val fn_to_string(Val a) {
    char buf[256];
    switch (a.type) {
        case VT_STRING: return a;
        case VT_INT: { int n = snprintf(buf, sizeof(buf), "%lld", (long long)a.u.i); return vs(buf, n); }
        case VT_FLOAT: {
            int64_t iv = (int64_t)a.u.f;
            if (a.u.f == (double)iv && a.u.f < 1e15 && a.u.f > -1e15) {
                int n = snprintf(buf, sizeof(buf), "%lld.0", (long long)iv); return vs(buf, n);
            }
            int n = snprintf(buf, sizeof(buf), "%g", a.u.f); return vs(buf, n);
        }
        case VT_BOOL: return a.u.b ? vsl("true") : vsl("false");
        case VT_NULL: return vsl("null");
        default: return vsl("");
    }
}
static Val fn_to_int(Val a) {
    switch (a.type) {
        case VT_INT: return a;
        case VT_FLOAT: return vi((int64_t)a.u.f);
        case VT_BOOL: return vi(a.u.b ? 1 : 0);
        case VT_STRING: return vi(strtol(a.u.s.p, NULL, 10));
        default: return vn();
    }
}
static Val fn_to_float(Val a) {
    switch (a.type) {
        case VT_FLOAT: return a;
        case VT_INT: return vf((double)a.u.i);
        case VT_STRING: return vf(strtod(a.u.s.p, NULL));
        default: return vn();
    }
}
static Val fn_to_bool(Val a) {
    switch (a.type) {
        case VT_BOOL: return a;
        case VT_INT: return vb(a.u.i != 0);
        case VT_STRING: return vb(strcmp(a.u.s.p, "true") == 0 || strcmp(a.u.s.p, "yes") == 0 || strcmp(a.u.s.p, "1") == 0);
        case VT_NULL: return vb(0);
        default: return vn();
    }
}

/* ---- Type checking ---- */
static Val fn_is_string(Val a) { return vb(a.type == VT_STRING); }
static Val fn_is_integer(Val a) { return vb(a.type == VT_INT); }
static Val fn_is_float(Val a) { return vb(a.type == VT_FLOAT); }
static Val fn_is_boolean(Val a) { return vb(a.type == VT_BOOL); }
static Val fn_is_null(Val a) { return vb(a.type == VT_NULL); }
static Val fn_is_array(Val a) { return vb(a.type == VT_ARRAY); }
static Val fn_is_object(Val a) { return vb(a.type == VT_OBJECT); }
static Val fn_is_nullish(Val a) {
    if (a.type == VT_NULL) return vb(1);
    if (a.type == VT_STRING) {
        for (int i = 0; i < a.u.s.n; i++)
            if (!isspace((unsigned char)a.u.s.p[i])) return vb(0);
        return vb(1);
    }
    return vb(0);
}

/* ---- Math ---- */
static Val fn_abs(Val a) {
    if (a.type == VT_INT) return vi(a.u.i < 0 ? -a.u.i : a.u.i);
    if (a.type == VT_FLOAT) return vf(a.u.f < 0.0 ? -a.u.f : a.u.f);
    return vn();
}
static Val fn_ceil_val(Val a) {
    if (a.type == VT_INT) return a;
    if (a.type == VT_FLOAT) { int64_t iv = (int64_t)a.u.f; if (a.u.f > (double)iv) iv++; return vi(iv); }
    return vn();
}
static Val fn_floor_val(Val a) {
    if (a.type == VT_INT) return a;
    if (a.type == VT_FLOAT) return vi((int64_t)a.u.f);
    return vn();
}
static Val fn_round_val(Val a) {
    if (a.type == VT_INT) return a;
    if (a.type == VT_FLOAT) return vi((int64_t)(a.u.f + 0.5));
    return vn();
}

/* ---- Object/array functions ---- */
static Val fn_keys(Val a) {
    if (a.type != VT_OBJECT) return vn();
    Val arr = va_new();
    for (int i = 0; i < a.u.o.len; i++) va_push(&arr, vsl(a.u.o.keys[i]));
    return arr;
}
static Val fn_values(Val a) {
    if (a.type != VT_OBJECT) return vn();
    Val arr = va_new();
    for (int i = 0; i < a.u.o.len; i++) va_push(&arr, a.u.o.vals[i]);
    return arr;
}
static Val fn_merge(Val a, Val b) {
    if (a.type != VT_OBJECT || b.type != VT_OBJECT) return vn();
    Val r = vo_new();
    for (int i = 0; i < a.u.o.len; i++) vo_set(&r, a.u.o.keys[i], a.u.o.vals[i]);
    for (int i = 0; i < b.u.o.len; i++) vo_set(&r, b.u.o.keys[i], b.u.o.vals[i]);
    return r;
}
static Val fn_compact(Val a) {
    if (a.type == VT_ARRAY) {
        Val r = va_new();
        for (int i = 0; i < a.u.a.len; i++) {
            Val item = a.u.a.items[i];
            if (item.type == VT_NULL) continue;
            if (item.type == VT_STRING && item.u.s.n == 0) continue;
            va_push(&r, item);
        }
        return r;
    }
    if (a.type == VT_OBJECT) {
        Val r = vo_new();
        for (int i = 0; i < a.u.o.len; i++) {
            Val item = a.u.o.vals[i];
            if (item.type == VT_NULL) continue;
            if (item.type == VT_STRING && item.u.s.n == 0) continue;
            vo_set(&r, a.u.o.keys[i], item);
        }
        return r;
    }
    return vn();
}
static Val fn_push_val(Val arr, Val item) {
    if (arr.type != VT_ARRAY) return vn();
    Val r = va_new();
    for (int i = 0; i < arr.u.a.len; i++) va_push(&r, arr.u.a.items[i]);
    va_push(&r, item);
    return r;
}

/* ---- JSON serialization ---- */
static int json_ser_str(const char *s, int slen, char *buf, int cap) {
    int pos = 0;
    if (pos < cap) buf[pos++] = \'"\';
    for (int i = 0; i < slen && pos < cap - 2; i++) {
        char c = s[i];
        if (c == \'"\' || c == \'\\\\\') { buf[pos++] = \'\\\\\'; buf[pos++] = c; }
        else if (c == \'\\n\') { buf[pos++] = \'\\\\\'; buf[pos++] = \'n\'; }
        else if (c == \'\\r\') { buf[pos++] = \'\\\\\'; buf[pos++] = \'r\'; }
        else if (c == \'\\t\') { buf[pos++] = \'\\\\\'; buf[pos++] = \'t\'; }
        else buf[pos++] = c;
    }
    if (pos < cap) buf[pos++] = \'"\';
    return pos;
}

static int json_serialize(Val v, char *buf, int cap) {
    int pos = 0;
    switch (v.type) {
        case VT_NULL: pos = snprintf(buf, cap, "null"); break;
        case VT_BOOL: pos = snprintf(buf, cap, v.u.b ? "true" : "false"); break;
        case VT_INT: pos = snprintf(buf, cap, "%lld", (long long)v.u.i); break;
        case VT_FLOAT: {
            int64_t iv = (int64_t)v.u.f;
            if (v.u.f == (double)iv && v.u.f < 1e15 && v.u.f > -1e15)
                pos = snprintf(buf, cap, "%lld.0", (long long)iv);
            else
                pos = snprintf(buf, cap, "%g", v.u.f);
            break;
        }
        case VT_STRING: pos = json_ser_str(v.u.s.p, v.u.s.n, buf, cap); break;
        case VT_ARRAY:
            if (pos < cap) buf[pos++] = \'[\';
            for (int i = 0; i < v.u.a.len; i++) {
                if (i > 0 && pos + 2 < cap) { buf[pos++] = \',\'; buf[pos++] = \' \'; }
                pos += json_serialize(v.u.a.items[i], buf + pos, cap - pos);
            }
            if (pos < cap) buf[pos++] = \']\';
            break;
        case VT_OBJECT: {
            int indices[256];
            int n = v.u.o.len < 256 ? v.u.o.len : 256;
            for (int i = 0; i < n; i++) indices[i] = i;
            for (int i = 0; i < n - 1; i++)
                for (int j = i + 1; j < n; j++)
                    if (strcmp(v.u.o.keys[indices[i]], v.u.o.keys[indices[j]]) > 0)
                        { int tmp = indices[i]; indices[i] = indices[j]; indices[j] = tmp; }
            if (pos < cap) buf[pos++] = \'{\';
            for (int i = 0; i < n; i++) {
                int idx = indices[i];
                if (i > 0 && pos + 2 < cap) { buf[pos++] = \',\'; buf[pos++] = \' \'; }
                pos += json_ser_str(v.u.o.keys[idx], (int)strlen(v.u.o.keys[idx]), buf + pos, cap - pos);
                if (pos + 2 < cap) { buf[pos++] = \':\'; buf[pos++] = \' \'; }
                pos += json_serialize(v.u.o.vals[idx], buf + pos, cap - pos);
            }
            if (pos < cap) buf[pos++] = \'}\';
            break;
        }
    }
    return pos;
}

static Val fn_encode_json(Val a) {
    char buf[65536];
    int n = json_serialize(a, buf, sizeof(buf));
    return vs(buf, n);
}

/* ---- JSON parsing ---- */
static Val json_parse(const char *s, int len, int *pos);

static void skip_ws(const char *s, int len, int *pos) {
    while (*pos < len && (s[*pos] == \' \' || s[*pos] == \'\\t\' || s[*pos] == \'\\n\' || s[*pos] == \'\\r\')) (*pos)++;
}

static Val json_parse_string(const char *s, int len, int *pos) {
    (*pos)++;
    int start = *pos;
    char *tmp = (char *)jit_alloc(len);
    int tn = 0;
    while (*pos < len && s[*pos] != \'"\') {
        if (s[*pos] == \'\\\\\' && *pos + 1 < len) {
            (*pos)++;
            switch (s[*pos]) {
                case \'n\': if(tmp) tmp[tn++] = \'\\n\'; break;
                case \'r\': if(tmp) tmp[tn++] = \'\\r\'; break;
                case \'t\': if(tmp) tmp[tn++] = \'\\t\'; break;
                default: if(tmp) tmp[tn++] = s[*pos]; break;
            }
        } else {
            if(tmp) tmp[tn++] = s[*pos];
        }
        (*pos)++;
    }
    if (*pos < len) (*pos)++;
    if (tmp) tmp[tn] = 0;
    Val v; memset(&v, 0, sizeof(v)); v.type = VT_STRING; v.u.s.p = tmp; v.u.s.n = tn; return v;
}

static Val json_parse_number(const char *s, int len, int *pos) {
    int start = *pos, is_float = 0;
    if (s[*pos] == \'-\') (*pos)++;
    while (*pos < len && s[*pos] >= \'0\' && s[*pos] <= \'9\') (*pos)++;
    if (*pos < len && s[*pos] == \'.\') { is_float = 1; (*pos)++; while (*pos < len && s[*pos] >= \'0\' && s[*pos] <= \'9\') (*pos)++; }
    if (*pos < len && (s[*pos] == \'e\' || s[*pos] == \'E\')) {
        is_float = 1; (*pos)++;
        if (*pos < len && (s[*pos] == \'+\' || s[*pos] == \'-\')) (*pos)++;
        while (*pos < len && s[*pos] >= \'0\' && s[*pos] <= \'9\') (*pos)++;
    }
    char buf[64]; int n = *pos - start; if (n >= 64) n = 63;
    memcpy(buf, s + start, n); buf[n] = 0;
    if (is_float) return vf(strtod(buf, NULL));
    return vi(strtol(buf, NULL, 10));
}

static Val json_parse(const char *s, int len, int *pos) {
    skip_ws(s, len, pos);
    if (*pos >= len) return vn();
    char c = s[*pos];
    if (c == \'n\') { *pos += 4; return vn(); }
    if (c == \'t\') { *pos += 4; return vb(1); }
    if (c == \'f\') { *pos += 5; return vb(0); }
    if (c == \'"\') return json_parse_string(s, len, pos);
    if (c == \'-\' || (c >= \'0\' && c <= \'9\')) return json_parse_number(s, len, pos);
    if (c == \'[\') {
        (*pos)++; Val arr = va_new();
        skip_ws(s, len, pos);
        if (*pos < len && s[*pos] == \']\') { (*pos)++; return arr; }
        while (*pos < len) {
            va_push(&arr, json_parse(s, len, pos));
            skip_ws(s, len, pos);
            if (*pos < len && s[*pos] == \',\') { (*pos)++; continue; }
            break;
        }
        skip_ws(s, len, pos);
        if (*pos < len && s[*pos] == \']\') (*pos)++;
        return arr;
    }
    if (c == \'{\') {
        (*pos)++; Val obj = vo_new();
        skip_ws(s, len, pos);
        if (*pos < len && s[*pos] == \'}\') { (*pos)++; return obj; }
        while (*pos < len) {
            skip_ws(s, len, pos);
            Val key = json_parse_string(s, len, pos);
            skip_ws(s, len, pos);
            if (*pos < len && s[*pos] == \':\') (*pos)++;
            Val val = json_parse(s, len, pos);
            if (key.type == VT_STRING) vo_set(&obj, key.u.s.p, val);
            skip_ws(s, len, pos);
            if (*pos < len && s[*pos] == \',\') { (*pos)++; continue; }
            break;
        }
        skip_ws(s, len, pos);
        if (*pos < len && s[*pos] == \'}\') (*pos)++;
        return obj;
    }
    return vn();
}

/* ---- Path operations ---- */
static Val path_get(Val obj, const char *path) {
    const char *p = path;
    if (*p == \'.\') p++;
    if (*p == 0) return obj;
    Val cur = obj;
    while (*p) {
        const char *dot = strchr(p, \'.\');
        int klen = dot ? (int)(dot - p) : (int)strlen(p);
        char key[256]; if (klen >= 256) klen = 255;
        memcpy(key, p, klen); key[klen] = 0;
        cur = vo_get(cur, key);
        if (cur.type == VT_NULL) return cur;
        p += klen;
        if (*p == \'.\') p++;
    }
    return cur;
}

static void path_set(Val *obj, const char *path, Val val) {
    const char *p = path;
    if (*p == \'.\') p++;
    if (*p == 0) { *obj = val; return; }
    const char *dot = strchr(p, \'.\');
    if (!dot) { vo_set(obj, p, val); return; }
    int klen = (int)(dot - p);
    char key[256]; if (klen >= 256) klen = 255;
    memcpy(key, p, klen); key[klen] = 0;
    Val child = vo_get(*obj, key);
    if (child.type != VT_OBJECT) child = vo_new();
    path_set(&child, dot, val);
    vo_set(obj, key, child);
}

static Val path_del(Val *obj, const char *path) {
    const char *p = path;
    if (*p == \'.\') p++;
    const char *dot = strchr(p, \'.\');
    if (!dot) {
        Val old = vo_get(*obj, p);
        vo_del(obj, p);
        return old;
    }
    int klen = (int)(dot - p);
    char key[256]; if (klen >= 256) klen = 255;
    memcpy(key, p, klen); key[klen] = 0;
    Val child = vo_get(*obj, key);
    if (child.type != VT_OBJECT) return vn();
    Val old = path_del(&child, dot + 1);
    vo_set(obj, key, child);
    return old;
}

/* ---- Index ---- */
static Val val_index(Val c, Val idx) {
    if (c.type == VT_ARRAY && idx.type == VT_INT) {
        int i = (int)idx.u.i;
        if (i < 0) i = c.u.a.len + i;
        if (i >= 0 && i < c.u.a.len) return c.u.a.items[i];
        return vn();
    }
    if (c.type == VT_OBJECT && idx.type == VT_STRING) return vo_get(c, idx.u.s.p);
    return vn();
}
'

// JitCodegen walks the AST and emits C source code.
struct JitCodegen {
mut:
	buf       strings.Builder
	temp_id   int
	declared  map[string]bool // tracks declared local variables
	supported bool            // false if unsupported construct encountered
}

fn new_jit_codegen() JitCodegen {
	return JitCodegen{
		buf: strings.new_builder(4096)
		supported: true
	}
}

// generate produces complete C source for the given AST expression.
// Returns the C source string, or an error if the AST contains unsupported constructs.
fn (mut g JitCodegen) generate(expr Expr) !string {
	g.buf.write_string(jit_c_preamble)
	g.buf.write_string('\nint jit_eval(const char *in_json, int in_len, char *out_json, int out_cap) {\n')
	g.buf.write_string('    jit_arena_reset();\n')
	g.buf.write_string('    int _parse_pos = 0;\n')
	g.buf.write_string('    Val ctx = json_parse(in_json, in_len, &_parse_pos);\n')
	g.buf.write_string('    Val _meta = vo_new();\n')

	result := g.gen_expr(expr)
	if !g.supported {
		return error('AST contains constructs not supported by JIT')
	}

	g.buf.write_string('    (void)${result};\n')
	g.buf.write_string('    int _out_len = json_serialize(ctx, out_json, out_cap);\n')
	g.buf.write_string('    if (_out_len < out_cap) out_json[_out_len] = 0;\n')
	g.buf.write_string('    return _out_len;\n')
	g.buf.write_string('}\n')
	return g.buf.str()
}

fn (mut g JitCodegen) next_temp() string {
	id := g.temp_id
	g.temp_id++
	return 't${id}'
}

fn (mut g JitCodegen) emit(s string) {
	g.buf.write_string('    ${s}\n')
}

fn escape_c_string(s string) string {
	mut out := strings.new_builder(s.len + 16)
	for ch in s {
		if ch == `"` {
			out.write_string('\\"')
		} else if ch == `\\` {
			out.write_string('\\\\')
		} else if ch == `\n` {
			out.write_string('\\n')
		} else if ch == `\r` {
			out.write_string('\\r')
		} else if ch == `\t` {
			out.write_string('\\t')
		} else {
			out.write_u8(ch)
		}
	}
	return out.str()
}

// gen_expr generates C code for an expression and returns the temp var name holding the result.
fn (mut g JitCodegen) gen_expr(expr Expr) string {
	if !g.supported {
		return 'vn()'
	}

	if expr is LiteralExpr {
		return g.gen_literal(expr)
	}
	if expr is ArrayExpr {
		return g.gen_array(expr)
	}
	if expr is ObjectExpr {
		return g.gen_object(expr)
	}
	if expr is IdentExpr {
		vname := 'var_${expr.name}'
		if vname !in g.declared {
			g.declared[vname] = true
			g.emit('Val ${vname} = vn();')
		}
		return vname
	}
	if expr is PathExpr {
		return g.gen_path_get(expr.path)
	}
	if expr is MetaPathExpr {
		return g.gen_meta_get(expr.path)
	}
	if expr is UnaryExpr {
		inner := g.gen_expr(expr.expr[0])
		t := g.next_temp()
		g.emit('Val ${t} = val_neg(${inner});')
		return t
	}
	if expr is NotExpr {
		inner := g.gen_expr(expr.expr[0])
		t := g.next_temp()
		g.emit('Val ${t} = vb(!truthy(${inner}));')
		return t
	}
	if expr is BinaryExpr {
		return g.gen_binary(expr)
	}
	if expr is AssignExpr {
		return g.gen_assign(expr)
	}
	if expr is MergeAssignExpr {
		return g.gen_merge_assign(expr)
	}
	if expr is IfExpr {
		return g.gen_if(expr)
	}
	if expr is BlockExpr {
		return g.gen_block(expr)
	}
	if expr is FnCallExpr {
		return g.gen_fn_call(expr)
	}
	if expr is IndexExpr {
		container := g.gen_expr(expr.expr[0])
		index := g.gen_expr(expr.index[0])
		t := g.next_temp()
		g.emit('Val ${t} = val_index(${container}, ${index});')
		return t
	}
	if expr is CoalesceExpr {
		return g.gen_coalesce(expr)
	}
	if expr is AbortExpr {
		// Abort: set a flag and return null. Simplified for JIT.
		t := g.next_temp()
		g.emit('Val ${t} = vn(); /* abort */')
		return t
	}
	if expr is ClosureExpr {
		g.supported = false
		return 'vn()'
	}
	return 'vn()'
}

fn (mut g JitCodegen) gen_literal(expr LiteralExpr) string {
	v := expr.value
	t := g.next_temp()
	match v {
		int {
			g.emit('Val ${t} = vi(${v});')
		}
		f64 {
			g.emit('Val ${t} = vf(${v});')
		}
		bool {
			b := if v { '1' } else { '0' }
			g.emit('Val ${t} = vb(${b});')
		}
		string {
			escaped := escape_c_string(v)
			g.emit('Val ${t} = vsl("${escaped}");')
		}
		VrlNull {
			g.emit('Val ${t} = vn();')
		}
		else {
			g.emit('Val ${t} = vn();')
		}
	}
	return t
}

fn (mut g JitCodegen) gen_array(expr ArrayExpr) string {
	t := g.next_temp()
	g.emit('Val ${t} = va_new();')
	for item in expr.items {
		item_var := g.gen_expr(item)
		g.emit('va_push(&${t}, ${item_var});')
	}
	return t
}

fn (mut g JitCodegen) gen_object(expr ObjectExpr) string {
	t := g.next_temp()
	g.emit('Val ${t} = vo_new();')
	for pair in expr.pairs {
		val_var := g.gen_expr(pair.value)
		escaped := escape_c_string(pair.key)
		g.emit('vo_set(&${t}, "${escaped}", ${val_var});')
	}
	return t
}

fn (mut g JitCodegen) gen_path_get(path string) string {
	t := g.next_temp()
	escaped := escape_c_string(path)
	g.emit('Val ${t} = path_get(ctx, "${escaped}");')
	return t
}

fn (mut g JitCodegen) gen_meta_get(path string) string {
	t := g.next_temp()
	if path == '%' {
		g.emit('Val ${t} = _meta;')
	} else {
		clean := if path.starts_with('%') { path[1..] } else { path }
		escaped := escape_c_string(clean)
		g.emit('Val ${t} = vo_get(_meta, "${escaped}");')
	}
	return t
}

fn (mut g JitCodegen) gen_binary(expr BinaryExpr) string {
	// Short-circuit operators need special handling
	if expr.op == '||' {
		left := g.gen_expr(expr.left[0])
		t := g.next_temp()
		g.emit('Val ${t};')
		g.emit('if (truthy(${left})) { ${t} = ${left}; } else {')
		right := g.gen_expr(expr.right[0])
		g.emit('    ${t} = ${right};')
		g.emit('}')
		return t
	}
	if expr.op == '&&' {
		left := g.gen_expr(expr.left[0])
		t := g.next_temp()
		g.emit('Val ${t};')
		g.emit('if (!truthy(${left})) { ${t} = ${left}; } else {')
		right := g.gen_expr(expr.right[0])
		g.emit('    ${t} = ${right};')
		g.emit('}')
		return t
	}

	left := g.gen_expr(expr.left[0])
	right := g.gen_expr(expr.right[0])
	t := g.next_temp()

	c_fn := match expr.op {
		'+' { 'val_add' }
		'-' { 'val_sub' }
		'*' { 'val_mul' }
		'/' { 'val_div' }
		'%' { 'val_mod' }
		'<' { 'val_lt' }
		'>' { 'val_gt' }
		'<=' { 'val_le' }
		'>=' { 'val_ge' }
		'==' { '' }
		'!=' { '' }
		else {
			g.supported = false
			''
		}
	}

	if expr.op == '==' {
		g.emit('Val ${t} = vb(val_eq(${left}, ${right}));')
	} else if expr.op == '!=' {
		g.emit('Val ${t} = vb(!val_eq(${left}, ${right}));')
	} else if c_fn.len > 0 {
		g.emit('Val ${t} = ${c_fn}(${left}, ${right});')
	} else {
		g.emit('Val ${t} = vn();')
	}
	return t
}

fn (mut g JitCodegen) gen_assign(expr AssignExpr) string {
	val := g.gen_expr(expr.value[0])
	target := expr.target[0]

	if target is PathExpr {
		escaped := escape_c_string(target.path)
		g.emit('path_set(&ctx, "${escaped}", ${val});')
		return val
	}
	if target is IdentExpr {
		vname := 'var_${target.name}'
		if vname !in g.declared {
			g.declared[vname] = true
			g.emit('Val ${vname} = ${val};')
		} else {
			g.emit('${vname} = ${val};')
		}
		return vname
	}
	if target is MetaPathExpr {
		if target.path == '%' {
			g.emit('_meta = ${val};')
		} else {
			clean := if target.path.starts_with('%') { target.path[1..] } else { target.path }
			escaped := escape_c_string(clean)
			g.emit('vo_set(&_meta, "${escaped}", ${val});')
		}
		return val
	}
	return val
}

fn (mut g JitCodegen) gen_merge_assign(expr MergeAssignExpr) string {
	val := g.gen_expr(expr.value[0])
	target := expr.target[0]

	if target is PathExpr {
		if target.path == '.' {
			g.emit('vo_merge(&ctx, ${val});')
			t := g.next_temp()
			g.emit('Val ${t} = ctx;')
			return t
		}
	}
	return val
}

fn (mut g JitCodegen) gen_if(expr IfExpr) string {
	cond := g.gen_expr(expr.condition[0])
	result := g.next_temp()
	g.emit('Val ${result};')
	g.emit('if (truthy(${cond})) {')
	then_var := g.gen_expr(expr.then_block[0])
	g.emit('    ${result} = ${then_var};')
	if expr.else_block.len > 0 {
		g.emit('} else {')
		else_var := g.gen_expr(expr.else_block[0])
		g.emit('    ${result} = ${else_var};')
	} else {
		g.emit('} else {')
		g.emit('    ${result} = vn();')
	}
	g.emit('}')
	return result
}

fn (mut g JitCodegen) gen_block(expr BlockExpr) string {
	mut last := 'vn()'
	for e in expr.exprs {
		last = g.gen_expr(e)
	}
	return last
}

fn (mut g JitCodegen) gen_coalesce(expr CoalesceExpr) string {
	primary := g.gen_expr(expr.expr[0])
	result := g.next_temp()
	g.emit('Val ${result};')
	g.emit('if (${primary}.type != VT_NULL) { ${result} = ${primary}; } else {')
	fallback := g.gen_expr(expr.default_[0])
	g.emit('    ${result} = ${fallback};')
	g.emit('}')
	return result
}

fn (mut g JitCodegen) gen_fn_call(expr FnCallExpr) string {
	name := if expr.name.ends_with('!') {
		expr.name[..expr.name.len - 1]
	} else {
		expr.name
	}

	// Special functions that operate on paths
	if name == 'del' {
		return g.gen_fn_del(expr)
	}
	if name == 'exists' {
		return g.gen_fn_exists(expr)
	}

	// Closures not supported in JIT
	if name == 'filter' || name == 'for_each' {
		g.supported = false
		return 'vn()'
	}

	// Evaluate args
	mut arg_vars := []string{}
	for arg in expr.args {
		arg_vars << g.gen_expr(arg)
	}

	t := g.next_temp()

	// Map to C function calls
	match name {
		'to_string', 'string' {
			if arg_vars.len > 0 {
				g.emit('Val ${t} = fn_to_string(${arg_vars[0]});')
			} else {
				g.emit('Val ${t} = vn();')
			}
		}
		'downcase' {
			g.emit('Val ${t} = fn_downcase(${arg_vars[0]});')
		}
		'upcase' {
			g.emit('Val ${t} = fn_upcase(${arg_vars[0]});')
		}
		'contains' {
			g.emit('Val ${t} = fn_contains(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'starts_with' {
			g.emit('Val ${t} = fn_starts_with(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'ends_with' {
			g.emit('Val ${t} = fn_ends_with(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'length' {
			g.emit('Val ${t} = fn_length(${arg_vars[0]});')
		}
		'strip_whitespace', 'trim' {
			g.emit('Val ${t} = fn_strip_whitespace(${arg_vars[0]});')
		}
		'replace' {
			g.emit('Val ${t} = fn_replace(${arg_vars[0]}, ${arg_vars[1]}, ${arg_vars[2]});')
		}
		'split' {
			g.emit('Val ${t} = fn_split(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'join' {
			sep := if arg_vars.len > 1 { arg_vars[1] } else { 'vsl("")' }
			g.emit('Val ${t} = fn_join(${arg_vars[0]}, ${sep});')
		}
		'to_int', 'int' {
			g.emit('Val ${t} = fn_to_int(${arg_vars[0]});')
		}
		'to_float', 'float' {
			g.emit('Val ${t} = fn_to_float(${arg_vars[0]});')
		}
		'to_bool', 'bool' {
			g.emit('Val ${t} = fn_to_bool(${arg_vars[0]});')
		}
		'is_string' {
			g.emit('Val ${t} = fn_is_string(${arg_vars[0]});')
		}
		'is_integer' {
			g.emit('Val ${t} = fn_is_integer(${arg_vars[0]});')
		}
		'is_float' {
			g.emit('Val ${t} = fn_is_float(${arg_vars[0]});')
		}
		'is_boolean' {
			g.emit('Val ${t} = fn_is_boolean(${arg_vars[0]});')
		}
		'is_null' {
			g.emit('Val ${t} = fn_is_null(${arg_vars[0]});')
		}
		'is_array' {
			g.emit('Val ${t} = fn_is_array(${arg_vars[0]});')
		}
		'is_object' {
			g.emit('Val ${t} = fn_is_object(${arg_vars[0]});')
		}
		'is_nullish' {
			g.emit('Val ${t} = fn_is_nullish(${arg_vars[0]});')
		}
		'keys' {
			g.emit('Val ${t} = fn_keys(${arg_vars[0]});')
		}
		'values' {
			g.emit('Val ${t} = fn_values(${arg_vars[0]});')
		}
		'merge' {
			g.emit('Val ${t} = fn_merge(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'compact' {
			g.emit('Val ${t} = fn_compact(${arg_vars[0]});')
		}
		'push' {
			g.emit('Val ${t} = fn_push_val(${arg_vars[0]}, ${arg_vars[1]});')
		}
		'encode_json' {
			g.emit('Val ${t} = fn_encode_json(${arg_vars[0]});')
		}
		'abs' {
			g.emit('Val ${t} = fn_abs(${arg_vars[0]});')
		}
		'ceil' {
			g.emit('Val ${t} = fn_ceil_val(${arg_vars[0]});')
		}
		'floor' {
			g.emit('Val ${t} = fn_floor_val(${arg_vars[0]});')
		}
		'round' {
			g.emit('Val ${t} = fn_round_val(${arg_vars[0]});')
		}
		'strlen' {
			g.emit('Val ${t} = fn_length(${arg_vars[0]});')
		}
		else {
			// Unsupported function - mark as unsupported
			g.supported = false
			g.emit('Val ${t} = vn();')
		}
	}
	return t
}

fn (mut g JitCodegen) gen_fn_del(expr FnCallExpr) string {
	if expr.args.len < 1 {
		return 'vn()'
	}
	arg := expr.args[0]
	t := g.next_temp()
	if arg is PathExpr {
		if arg.path == '.' {
			g.emit('Val ${t} = ctx;')
			g.emit('ctx = vo_new();')
		} else {
			escaped := escape_c_string(arg.path)
			g.emit('Val ${t} = path_del(&ctx, "${escaped}");')
		}
	} else {
		// Evaluate the argument if it's not a path
		v := g.gen_expr(arg)
		g.emit('Val ${t} = ${v};')
	}
	return t
}

fn (mut g JitCodegen) gen_fn_exists(expr FnCallExpr) string {
	if expr.args.len < 1 {
		return 'vb(0)'
	}
	arg := expr.args[0]
	t := g.next_temp()
	if arg is PathExpr {
		if arg.path == '.' {
			g.emit('Val ${t} = vb(1);')
		} else {
			escaped := escape_c_string(arg.path)
			g.emit('Val ${t} = vb(path_get(ctx, "${escaped}").type != VT_NULL);')
		}
	} else {
		g.emit('Val ${t} = vb(0);')
	}
	return t
}

// jit_can_compile checks whether an AST can be fully JIT-compiled.
pub fn jit_can_compile(expr Expr) bool {
	mut g := new_jit_codegen()
	g.gen_expr(expr)
	return g.supported
}

// jit_generate_c produces the complete C source for a VRL AST.
pub fn jit_generate_c(expr Expr) !string {
	mut g := new_jit_codegen()
	return g.generate(expr)
}
