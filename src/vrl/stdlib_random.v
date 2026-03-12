module vrl

import rand
import time

// random_int(min, max)
fn fn_random_int(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('random_int requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	min := match a0 {
		i64 { a0 }
		else { return error('random_int min must be integer') }
	}
	max := match a1 {
		i64 { a1 }
		else { return error('random_int max must be integer') }
	}
	if min > max {
		return error('min must be <= max')
	}
	if min == max {
		return VrlValue(min)
	}
	val := rand.int_in_range(int(min), int(max + 1)) or { int(min) }
	return VrlValue(i64(val))
}

// random_float(min, max)
fn fn_random_float(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('random_float requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	min := match a0 {
		f64 { a0 }
		i64 { f64(a0) }
		else { return error('random_float min must be number') }
	}
	max := match a1 {
		f64 { a1 }
		i64 { f64(a1) }
		else { return error('random_float max must be number') }
	}
	if min > max {
		return error('min must be <= max')
	}
	val := rand.f64_in_range(min, max) or { min }
	return VrlValue(val)
}

// random_bool()
fn fn_random_bool() !VrlValue {
	return VrlValue(rand.intn(2) or { 0 } == 1)
}

// random_bytes(length)
fn fn_random_bytes(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('random_bytes requires 1 argument')
	}
	a := args[0]
	length := match a {
		i64 { a }
		else { return error('random_bytes requires an integer') }
	}
	if length < 0 {
		return error('length must be non-negative')
	}
	mut bytes := []u8{len: int(length)}
	for i in 0 .. int(length) {
		bytes[i] = u8(rand.intn(256) or { 0 })
	}
	return VrlValue(bytes.bytestr())
}

// UUID v7 monotonic counter state, matching the Rust uuid crate's ContextV7.
//
// The Rust crate uses a 42-bit counter spanning rand_a (12 bits) and
// 30 bits of rand_b.  On each new millisecond the counter is reseeded
// with a random 41-bit value (high bit clear so there is room to
// increment).  Within the same millisecond the counter increments by 1,
// guaranteeing strict monotonic ordering.
//
// The remaining 32 bits of rand_b are filled with random data.
const uuid_v7_counter_bits = 42
const uuid_v7_reseed_mask = u64(0x0000_01FF_FFFF_FFFF) // 41 bits (high bit of 42 clear)
const uuid_v7_max_counter = u64(0x0000_03FF_FFFF_FFFF) // 42 bits all set

// Monotonic counter state stored as C statics (avoids V's -enable-globals).
#flag -I @VMODROOT/src/vrl
#include "uuid_v7_state.h"

fn C.uuid_v7_get_last_ms() i64
fn C.uuid_v7_set_last_ms(ms i64)
fn C.uuid_v7_get_counter() u64
fn C.uuid_v7_set_counter(c u64)

// uuid_v7_next_counter returns the next (counter, random32, effective_ms) tuple
// for a given millisecond timestamp.  counter is 42 bits, random32 is 32 bits.
fn uuid_v7_next_counter(ts_ms i64) (u64, u32, i64) {
	random32 := u32(rand.intn(0x7FFF_FFFE) or { 0 }) ^ (u32(rand.intn(0x7FFF_FFFE) or { 0 }) << 15)
	last_ms := C.uuid_v7_get_last_ms()
	if ts_ms != last_ms {
		// New millisecond — reseed counter with random 41-bit value
		seed := u64(rand.intn(0x7FFF_FFFE) or { 0 }) | (u64(rand.intn(0x7FFF_FFFE) or { 0 }) << 31)
		counter := seed & uuid_v7_reseed_mask
		C.uuid_v7_set_counter(counter)
		C.uuid_v7_set_last_ms(ts_ms)
		return counter, random32, ts_ms
	}
	// Same millisecond — increment
	mut counter := C.uuid_v7_get_counter() + 1
	mut effective_ms := ts_ms
	if counter > uuid_v7_max_counter {
		// Overflow: advance timestamp by 1 ms and reseed
		effective_ms = ts_ms + 1
		C.uuid_v7_set_last_ms(effective_ms)
		seed := u64(rand.intn(0x7FFF_FFFE) or { 0 }) | (u64(rand.intn(0x7FFF_FFFE) or { 0 }) << 31)
		counter = seed & uuid_v7_reseed_mask
	}
	C.uuid_v7_set_counter(counter)
	return counter, random32, effective_ms
}

// uuid_v7() - time-ordered UUID with 42-bit monotonic counter
fn fn_uuid_v7(args []VrlValue) !VrlValue {
	mut ts_ms := i64(0)
	if args.len > 0 {
		a := args[0]
		match a {
			Timestamp {
				if rust_vrl_compat {
					// Reproduce Rust VRL's quirk: chrono's timestamp_nanos_opt()
					// returns total nanoseconds since epoch as i64, then the code
					// casts it to u32 (truncating), and passes it to
					// uuid::Timestamp::from_unix(NoContext, seconds, nanos_as_u32).
					// The uuid crate interprets that as sub-second nanoseconds,
					// so the truncated value shifts the millisecond timestamp.
					secs := i64(a.t.unix())
					total_nanos := a.t.unix_micro() * 1000
					truncated_nanos := u32(total_nanos)
					ts_ms = secs * 1000 + i64(truncated_nanos) / 1_000_000
				} else {
					ts_ms = a.t.unix_micro() / 1000
				}
			}
			else {
				return error('uuid_v7 timestamp must be a timestamp')
			}
		}
	} else {
		ts_ms = time.now().unix_micro() / 1000
	}

	counter, random32, effective_ms := uuid_v7_next_counter(ts_ms)

	// Build the 16-byte UUID
	// Bytes 0-5: 48-bit millisecond timestamp (big-endian)
	// Bytes 6-7: version (4 bits = 0x7) + counter high 12 bits
	// Byte 8:    variant (2 bits = 0b10) + counter next 6 bits
	// Bytes 9-11: counter low 24 bits
	// Bytes 12-15: random 32 bits
	mut buf := []u8{len: 16}

	// Timestamp (48 bits, big-endian)
	buf[0] = u8((effective_ms >> 40) & 0xFF)
	buf[1] = u8((effective_ms >> 32) & 0xFF)
	buf[2] = u8((effective_ms >> 24) & 0xFF)
	buf[3] = u8((effective_ms >> 16) & 0xFF)
	buf[4] = u8((effective_ms >> 8) & 0xFF)
	buf[5] = u8(effective_ms & 0xFF)

	// Counter spans 42 bits across bytes 6-11:
	//   byte 6: version(4) + counter[41:38]  (high 4 bits of counter)
	//   byte 7: counter[37:30]               (next 8 bits)
	//   byte 8: variant(2) + counter[29:24]  (next 6 bits)
	//   bytes 9-11: counter[23:0]            (low 24 bits)
	buf[6] = 0x70 | u8((counter >> 38) & 0x0F)
	buf[7] = u8((counter >> 30) & 0xFF)
	buf[8] = 0x80 | u8((counter >> 24) & 0x3F)
	buf[9] = u8((counter >> 16) & 0xFF)
	buf[10] = u8((counter >> 8) & 0xFF)
	buf[11] = u8(counter & 0xFF)

	// Random 32 bits
	buf[12] = u8((random32 >> 24) & 0xFF)
	buf[13] = u8((random32 >> 16) & 0xFF)
	buf[14] = u8((random32 >> 8) & 0xFF)
	buf[15] = u8(random32 & 0xFF)

	h := '0123456789abcdef'
	mut result := []u8{len: 36}
	mut pos := 0
	for i in 0 .. 16 {
		if i == 4 || i == 6 || i == 8 || i == 10 {
			result[pos] = `-`
			pos++
		}
		result[pos] = h[buf[i] >> 4]
		pos++
		result[pos] = h[buf[i] & 0x0F]
		pos++
	}
	return VrlValue(result.bytestr())
}

// get_hostname()
fn fn_get_hostname() !VrlValue {
	hostname := os_get_hostname()
	return VrlValue(hostname)
}

fn os_get_hostname() string {
	$if linux {
		mut buf := [256]u8{}
		res := C.gethostname(&buf[0], 256)
		if res == 0 {
			mut len := 0
			for len < 256 && buf[len] != 0 {
				len++
			}
			return unsafe { (&buf[0]).vstring_with_len(len) }.clone()
		}
	}
	return 'localhost'
}

fn C.gethostname(name &u8, len int) int
