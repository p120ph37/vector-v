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

// uuid_v7() - time-ordered UUID
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
	// UUID v7: 48 bits of timestamp, 4 bits version (7), 12 bits random, 2 bits variant (10), 62 bits random
	mut buf := []u8{len: 16}
	// Timestamp (48 bits, big-endian)
	buf[0] = u8((ts_ms >> 40) & 0xFF)
	buf[1] = u8((ts_ms >> 32) & 0xFF)
	buf[2] = u8((ts_ms >> 24) & 0xFF)
	buf[3] = u8((ts_ms >> 16) & 0xFF)
	buf[4] = u8((ts_ms >> 8) & 0xFF)
	buf[5] = u8(ts_ms & 0xFF)
	// Random bytes for rest
	for i in 6 .. 16 {
		buf[i] = u8(rand.intn(256) or { 0 })
	}
	// Set version (7) in bits 48-51
	buf[6] = (buf[6] & 0x0F) | 0x70
	// Set variant (10) in bits 64-65
	buf[8] = (buf[8] & 0x3F) | 0x80

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
