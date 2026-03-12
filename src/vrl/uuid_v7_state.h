#include <stdint.h>

static int64_t  _uuid_v7_last_ms  = 0;
static uint64_t _uuid_v7_counter  = 0;

static inline int64_t  uuid_v7_get_last_ms(void)        { return _uuid_v7_last_ms; }
static inline void     uuid_v7_set_last_ms(int64_t ms)   { _uuid_v7_last_ms = ms; }
static inline uint64_t uuid_v7_get_counter(void)         { return _uuid_v7_counter; }
static inline void     uuid_v7_set_counter(uint64_t c)   { _uuid_v7_counter = c; }
