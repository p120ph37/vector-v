module transforms

import event
import time

// --- sample.v coverage ---

fn test_sample_invalid_rate_zero() {
	// Covers line 24: rate must be >= 1 error
	mut opts := map[string]string{}
	opts['rate'] = '0'
	if _ := new_sample(opts) {
		assert false, 'expected error for rate=0'
	} else {
		assert err.msg().contains('rate must be >= 1')
	}
}

fn test_sample_invalid_rate_negative() {
	// Covers line 24: rate must be >= 1 error with negative value
	mut opts := map[string]string{}
	opts['rate'] = '-5'
	if _ := new_sample(opts) {
		assert false, 'expected error for negative rate'
	} else {
		assert err.msg().contains('rate must be >= 1')
	}
}

fn test_sample_key_field_deterministic_pass_and_drop() {
	// Covers lines 49 and 51: deterministic sampling via key_field hash
	// With rate=2, about half of keys will hash to pass (h%2==0) and half drop
	mut opts := map[string]string{}
	opts['rate'] = '2'
	opts['key_field'] = 'id'
	t := new_sample(opts) or { return }

	mut passed := 0
	mut dropped := 0
	// Try many different keys to ensure both paths are hit
	for i in 0 .. 100 {
		mut log := event.new_log('test')
		log.set('id', event.Value('key_${i}'))
		result := t.transform(event.Event(log)) or { return }
		if result.len == 1 {
			passed++
		} else {
			dropped++
		}
	}
	// With rate=2 and 100 keys, we expect both passes and drops
	assert passed > 0, 'expected some events to pass with key_field sampling'
	assert dropped > 0, 'expected some events to be dropped with key_field sampling'
}

fn test_sample_random_drops_events() {
	// Covers line 59: random sampling drops events (return [])
	// With rate=1000000, almost all events are dropped randomly
	mut opts := map[string]string{}
	opts['rate'] = '1000000'
	t := new_sample(opts) or { return }

	mut dropped := 0
	for _ in 0 .. 50 {
		ev := event.Event(event.new_log('test'))
		result := t.transform(ev) or { return }
		if result.len == 0 {
			dropped++
		}
	}
	assert dropped > 0, 'expected some events to be dropped with high rate'
}

fn test_sample_check_condition_false() {
	// Covers line 79: check_sample_condition returns false for non-matching condition
	mut opts := map[string]string{}
	opts['rate'] = '1000000'
	opts['exclude'] = '.level == "error"'
	t := new_sample(opts) or { return }

	// Event with level != "error" should NOT bypass sampling via exclude
	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	// The exclude condition won't match, so the event goes through random sampling
	// With rate=1000000 it will almost certainly be dropped
	mut dropped := 0
	for _ in 0 .. 20 {
		mut l := event.new_log('test')
		l.set('level', event.Value('info'))
		result := t.transform(event.Event(l)) or { return }
		if result.len == 0 {
			dropped++
		}
	}
	assert dropped > 0, 'non-matching exclude condition should not bypass sampling'
}

fn test_sample_check_condition_no_equals() {
	// Covers line 79: check_sample_condition returns false when condition has no ==
	mut opts := map[string]string{}
	opts['rate'] = '1000000'
	opts['exclude'] = '.level'
	t := new_sample(opts) or { return }

	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	// Condition without == should return false, so no bypass
	mut dropped := 0
	for _ in 0 .. 20 {
		mut l := event.new_log('test')
		l.set('level', event.Value('error'))
		result := t.transform(event.Event(l)) or { return }
		if result.len == 0 {
			dropped++
		}
	}
	assert dropped > 0, 'condition without == should not match'
}

// --- throttle.v coverage ---

fn test_throttle_invalid_threshold_zero() {
	// Covers line 34: threshold must be >= 1 error
	mut opts := map[string]string{}
	opts['threshold'] = '0'
	if _ := new_throttle(opts) {
		assert false, 'expected error for threshold=0'
	} else {
		assert err.msg().contains('threshold must be >= 1')
	}
}

fn test_throttle_invalid_threshold_negative() {
	// Covers line 34: threshold must be >= 1 error with negative value
	mut opts := map[string]string{}
	opts['threshold'] = '-3'
	if _ := new_throttle(opts) {
		assert false, 'expected error for negative threshold'
	} else {
		assert err.msg().contains('threshold must be >= 1')
	}
}

fn test_throttle_token_refill_after_window() {
	// Covers lines 79-82, 84: token bucket refill logic
	// Use window_secs=1 and exhaust tokens, then wait for refill
	mut opts := map[string]string{}
	opts['threshold'] = '2'
	opts['window_secs'] = '1'
	mut t := new_throttle(opts) or { return }

	// Exhaust the 2 tokens
	for _ in 0 .. 2 {
		ev := event.Event(event.new_log('msg'))
		t.transform(ev) or { return }
	}

	// Verify tokens are exhausted
	ev_blocked := event.Event(event.new_log('blocked'))
	result_blocked := t.transform(ev_blocked) or { return }
	assert result_blocked.len == 0, 'should be throttled after exhausting tokens'

	// Manually manipulate bucket to simulate time passing
	// Set the last_ts far in the past so elapsed >= window
	mut bucket := t.buckets['_default_'] or { return }
	// Move last_ts back by 3 seconds to ensure refill
	bucket.last_ts = time.unix(time.now().unix() - 3)
	t.buckets['_default_'] = bucket

	// Now the next event should trigger refill and pass
	ev_after := event.Event(event.new_log('after refill'))
	result_after := t.transform(ev_after) or { return }
	assert result_after.len == 1, 'event after token refill should pass'
}

// --- registry.v coverage ---

fn test_build_transform_aws_ec2_metadata() {
	// Cover the aws_ec2_metadata branch in build_transform
	t := build_transform('aws_ec2_metadata', map[string]string{}) or { return }
	assert t is Ec2MetadataTransform
}

fn test_apply_transform_sample_via_registry() {
	// Cover the SampleTransform branch in apply_transform
	mut t := build_transform('sample', {
		'rate': '1'
	}) or { return }

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev) or { return }
	assert result.len == 1
}

fn test_apply_transform_exclusive_route_via_registry() {
	// Cover the ExclusiveRouteTransform branch in apply_transform
	mut t := build_transform('exclusive_route', {
		'routes.errors.condition': '.level == "error"'
	}) or { return }

	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := apply_transform(mut t, ev) or { return }
	assert result.len == 1
}

fn test_apply_transform_remap_via_registry() {
	// Cover the RemapTransform branch in apply_transform
	mut t := build_transform('remap', {
		'source': '.env = "test"'
	}) or { return }

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev) or { return }
	assert result.len == 1
}
