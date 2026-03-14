module vrl

import time

// Tests for vrllib_random.v

fn test_random_int_basic() {
	result := fn_random_int([VrlValue(i64(1)), VrlValue(i64(10))]) or {
		assert false, 'random_int basic: ${err}'
		return
	}
	n := result as i64
	assert n >= 1 && n <= 10
}

fn test_random_int_equal_min_max() {
	result := fn_random_int([VrlValue(i64(5)), VrlValue(i64(5))]) or {
		assert false, 'random_int equal: ${err}'
		return
	}
	assert result == VrlValue(i64(5))
}

fn test_random_int_min_gt_max() {
	fn_random_int([VrlValue(i64(10)), VrlValue(i64(1))]) or {
		assert err.msg().contains('min must be <= max')
		return
	}
	assert false, 'expected error'
}

fn test_random_int_too_few_args() {
	fn_random_int([VrlValue(i64(1))]) or {
		assert err.msg().contains('requires 2')
		return
	}
	assert false, 'expected error'
}

fn test_random_int_bad_type_min() {
	fn_random_int([VrlValue('a'), VrlValue(i64(1))]) or {
		assert err.msg().contains('min must be integer')
		return
	}
	assert false, 'expected error'
}

fn test_random_int_bad_type_max() {
	fn_random_int([VrlValue(i64(1)), VrlValue('b')]) or {
		assert err.msg().contains('max must be integer')
		return
	}
	assert false, 'expected error'
}

fn test_random_float_basic() {
	result := fn_random_float([VrlValue(f64(0.0)), VrlValue(f64(1.0))]) or {
		assert false, 'random_float basic: ${err}'
		return
	}
	f := result as f64
	assert f >= 0.0 && f <= 1.0
}

fn test_random_float_int_args() {
	result := fn_random_float([VrlValue(i64(0)), VrlValue(i64(10))]) or {
		assert false, 'random_float int args: ${err}'
		return
	}
	f := result as f64
	assert f >= 0.0 && f <= 10.0
}

fn test_random_float_min_gt_max() {
	fn_random_float([VrlValue(f64(10.0)), VrlValue(f64(1.0))]) or {
		assert err.msg().contains('min must be <= max')
		return
	}
	assert false, 'expected error'
}

fn test_random_float_too_few_args() {
	fn_random_float([]) or {
		assert err.msg().contains('requires 2')
		return
	}
	assert false, 'expected error'
}

fn test_random_float_bad_type_min() {
	fn_random_float([VrlValue('a'), VrlValue(f64(1.0))]) or {
		assert err.msg().contains('min must be number')
		return
	}
	assert false, 'expected error'
}

fn test_random_float_bad_type_max() {
	fn_random_float([VrlValue(f64(0.0)), VrlValue('b')]) or {
		assert err.msg().contains('max must be number')
		return
	}
	assert false, 'expected error'
}

fn test_random_bool() {
	result := fn_random_bool() or {
		assert false, 'random_bool: ${err}'
		return
	}
	_ = result as bool
}

fn test_random_bytes_basic() {
	result := fn_random_bytes([VrlValue(i64(16))]) or {
		assert false, 'random_bytes: ${err}'
		return
	}
	s := result as string
	assert s.len == 16
}

fn test_random_bytes_zero() {
	result := fn_random_bytes([VrlValue(i64(0))]) or {
		assert false, 'random_bytes zero: ${err}'
		return
	}
	s := result as string
	assert s.len == 0
}

fn test_random_bytes_negative() {
	fn_random_bytes([VrlValue(i64(-1))]) or {
		assert err.msg().contains('non-negative')
		return
	}
	assert false, 'expected error'
}

fn test_random_bytes_no_args() {
	fn_random_bytes([]) or {
		assert err.msg().contains('requires 1')
		return
	}
	assert false, 'expected error'
}

fn test_random_bytes_bad_type() {
	fn_random_bytes([VrlValue('abc')]) or {
		assert err.msg().contains('requires an integer')
		return
	}
	assert false, 'expected error'
}

fn test_uuid_v7_no_args() {
	result := fn_uuid_v7([]) or {
		assert false, 'uuid_v7 no args: ${err}'
		return
	}
	s := result as string
	assert s.len == 36
	assert s[14] == `7` // version 7
}

fn test_uuid_v7_with_timestamp() {
	t := Timestamp{
		t: time.new(year: 2024, month: 6, day: 15, hour: 12, minute: 0, second: 0)
	}
	result := fn_uuid_v7([VrlValue(t)]) or {
		assert false, 'uuid_v7 with ts: ${err}'
		return
	}
	s := result as string
	assert s.len == 36
	assert s[14] == `7`
}

fn test_uuid_v7_bad_type() {
	fn_uuid_v7([VrlValue('not_a_timestamp')]) or {
		assert err.msg().contains('timestamp must be a timestamp')
		return
	}
	assert false, 'expected error'
}

fn test_uuid_v7_monotonic() {
	// Two calls in same ms should produce monotonically increasing UUIDs
	r1 := fn_uuid_v7([]) or {
		assert false, 'uuid_v7 mono 1: ${err}'
		return
	}
	r2 := fn_uuid_v7([]) or {
		assert false, 'uuid_v7 mono 2: ${err}'
		return
	}
	s1 := r1 as string
	s2 := r2 as string
	assert s1 != s2
}

fn test_uuid_v7_next_counter_new_ms() {
	// Reset state for testing
	uuid_v7_last_ms = 0
	uuid_v7_counter_val = 0
	c1, _, _ := uuid_v7_next_counter(1000)
	assert c1 <= uuid_v7_reseed_mask
}

fn test_uuid_v7_next_counter_same_ms() {
	uuid_v7_last_ms = 1000
	uuid_v7_counter_val = 100
	c1, _, _ := uuid_v7_next_counter(1000)
	assert c1 == 101
}

fn test_uuid_v7_next_counter_overflow() {
	uuid_v7_last_ms = 1000
	uuid_v7_counter_val = uuid_v7_max_counter
	_, _, effective_ms := uuid_v7_next_counter(1000)
	assert effective_ms == 1001 // advanced by 1 ms on overflow
}

fn test_get_hostname() {
	result := fn_get_hostname() or {
		assert false, 'get_hostname: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
}
