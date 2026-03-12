module vrl

import math
import os
import rand
import regex.pcre
import time

// normalize_regex_pattern translates Rust-style regex anchors to PCRE-compatible equivalents.
// Rust regex uses \A (start of string) and \z (end of string) which V's pcre module doesn't support.
fn normalize_regex_pattern(pattern string) string {
	if !pattern.contains('\\A') && !pattern.contains('\\z') {
		return pattern
	}
	mut result := []u8{cap: pattern.len}
	mut i := 0
	for i < pattern.len {
		if i + 1 < pattern.len && pattern[i] == `\\` {
			if pattern[i + 1] == `A` {
				result << `^`
				i += 2
				continue
			} else if pattern[i + 1] == `z` {
				result << `$`
				i += 2
				continue
			}
		}
		result << pattern[i]
		i++
	}
	return result.bytestr()
}

// resolve_named_args evaluates function arguments and resolves named args into a map.
fn (mut rt Runtime) resolve_named_args(expr FnCallExpr) !([]VrlValue, map[string]VrlValue) {
	mut positional := []VrlValue{}
	mut named := map[string]VrlValue{}
	for i, arg in expr.args {
		val := rt.eval(arg)!
		if i < expr.arg_names.len && expr.arg_names[i].len > 0 {
			named[expr.arg_names[i]] = val
		} else {
			positional << val
		}
	}
	return positional, named
}

// get_named_bool gets a boolean named argument with a default.
fn get_named_bool(named map[string]VrlValue, key string, default_val bool) bool {
	if v := named[key] {
		match v {
			bool { return v }
			else { return default_val }
		}
	}
	return default_val
}

// get_named_int gets an integer named argument with a default.
fn get_named_int(named map[string]VrlValue, key string, default_val i64) i64 {
	if v := named[key] {
		match v {
			i64 { return v }
			else { return default_val }
		}
	}
	return default_val
}

// get_named_string gets a string named argument with a default.
fn get_named_string(named map[string]VrlValue, key string, default_val string) string {
	if v := named[key] {
		match v {
			string { return v }
			else { return default_val }
		}
	}
	return default_val
}

// eval_fn_call_named handles function calls with named arguments.
fn (mut rt Runtime) eval_fn_call_named(name string, expr FnCallExpr) !VrlValue {
	pos, named := rt.resolve_named_args(expr)!
	match name {
		'compact' {
			if pos.len < 1 { return error('compact requires 1 argument') }
			return fn_compact_named(pos[0], named)
		}
		'contains' {
			if pos.len < 2 { return error('contains requires 2 arguments') }
			cs := get_named_bool(named, 'case_sensitive', true)
			mut args := [pos[0], pos[1]]
			args << VrlValue(cs)
			return fn_contains(args)
		}
		'starts_with' {
			if pos.len < 2 { return error('starts_with requires 2 arguments') }
			cs := get_named_bool(named, 'case_sensitive', true)
			mut args := [pos[0], pos[1]]
			args << VrlValue(cs)
			return fn_starts_with(args)
		}
		'ends_with' {
			if pos.len < 2 { return error('ends_with requires 2 arguments') }
			cs := get_named_bool(named, 'case_sensitive', true)
			mut args := [pos[0], pos[1]]
			args << VrlValue(cs)
			return fn_ends_with(args)
		}
		'replace' {
			if pos.len < 3 { return error('replace requires 3 arguments') }
			count := get_named_int(named, 'count', -1)
			mut args := [pos[0], pos[1], pos[2]]
			args << VrlValue(count)
			return fn_replace(args)
		}
		'split' {
			if pos.len < 2 { return error('split requires 2 arguments') }
			limit := get_named_int(named, 'limit', 0)
			mut args := [pos[0], pos[1]]
			args << VrlValue(limit)
			return fn_split(args)
		}
		'truncate' {
			if pos.len < 1 { return error('truncate requires at least 1 argument') }
			limit := if pos.len > 1 { pos[1] } else { VrlValue(get_named_int(named, 'limit', 0)) }
			suffix := get_named_string(named, 'suffix', '')
			ellipsis := get_named_bool(named, 'ellipsis', false)
			eff_suffix := if suffix.len > 0 { suffix } else { if ellipsis { '...' } else { '' } }
			mut args := [pos[0], limit]
			args << VrlValue(eff_suffix)
			return fn_truncate(args)
		}
		'flatten' {
			if pos.len < 1 { return error('flatten requires 1 argument') }
			sep := get_named_string(named, 'separator', '.')
			mut args := [pos[0]]
			args << VrlValue(sep)
			return fn_flatten(args)
		}
		'format_number' {
			if pos.len < 1 { return error('format_number requires 1 argument') }
			scale := if pos.len > 1 { pos[1] } else { VrlValue(get_named_int(named, 'scale', -1)) }
			dec_sep := get_named_string(named, 'decimal_separator', '.')
			grp_sep := get_named_string(named, 'grouping_separator', '')
			mut args := [pos[0], scale]
			args << VrlValue(dec_sep)
			args << VrlValue(grp_sep)
			return fn_format_number(args)
		}
		'ceil' {
			if pos.len < 1 { return error('ceil requires 1 argument') }
			prec := if pos.len > 1 { pos[1] } else { VrlValue(get_named_int(named, 'precision', 0)) }
			return fn_ceil([pos[0], prec])
		}
		'floor' {
			if pos.len < 1 { return error('floor requires 1 argument') }
			prec := if pos.len > 1 { pos[1] } else { VrlValue(get_named_int(named, 'precision', 0)) }
			return fn_floor([pos[0], prec])
		}
		'round' {
			if pos.len < 1 { return error('round requires 1 argument') }
			prec := if pos.len > 1 { pos[1] } else { VrlValue(get_named_int(named, 'precision', 0)) }
			return fn_round([pos[0], prec])
		}
		'encode_json' {
			if pos.len < 1 { return error('encode_json requires 1 argument') }
			pretty := get_named_bool(named, 'pretty', false)
			mut args := [pos[0]]
			args << VrlValue(pretty)
			return fn_encode_json(args)
		}
		'to_unix_timestamp' {
			if pos.len < 1 { return error('to_unix_timestamp requires 1 argument') }
			unit := get_named_string(named, 'unit', 'seconds')
			mut args := [pos[0]]
			args << VrlValue(unit)
			return fn_to_unix_timestamp(args)
		}
		'parse_json', 'decode_json' {
			if pos.len < 1 { return error('parse_json requires 1 argument') }
			max_depth := get_named_int(named, 'max_depth', 0)
			mut args := [pos[0]]
			args << VrlValue(max_depth)
			return fn_decode_json(args)
		}
		'assert' {
			if pos.len < 1 { return error('assert requires 1 argument') }
			msg := get_named_string(named, 'message', 'assertion failed')
			mut args := [pos[0]]
			args << VrlValue(msg)
			return fn_assert(args)
		}
		'assert_eq' {
			if pos.len < 2 { return error('assert_eq requires 2 arguments') }
			msg := get_named_string(named, 'message', '')
			mut args := [pos[0], pos[1]]
			if msg.len > 0 { args << VrlValue(msg) }
			return fn_assert_eq(args)
		}
		'contains_all' {
			if pos.len < 2 { return error('contains_all requires 2 arguments') }
			cs := get_named_bool(named, 'case_sensitive', true)
			mut args := [pos[0], pos[1]]
			args << VrlValue(cs)
			return fn_contains_all(args)
		}
		'unflatten' {
			if pos.len < 1 { return error('unflatten requires 1 argument') }
			sep := get_named_string(named, 'separator', '.')
			mut args := [pos[0]]
			args << VrlValue(sep)
			return fn_unflatten(args)
		}
		'find' {
			if pos.len < 2 { return error('find requires 2 arguments') }
			from := get_named_int(named, 'from', 0)
			mut args := [pos[0], pos[1]]
			args << VrlValue(from)
			return fn_find(args)
		}
		'get' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('get requires value argument') }
			path := if v := named['path'] { v } else if pos.len > 1 { pos[1] } else { return error('get requires path argument') }
			return fn_get([value, path])
		}
		'set' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('set requires value argument') }
			path := if v := named['path'] { v } else if pos.len > 1 { pos[1] } else { return error('set requires path argument') }
			data := if v := named['data'] { v } else if pos.len > 2 { pos[2] } else { return error('set requires data argument') }
			return fn_set([value, path, data])
		}
		'log' {
			return VrlValue(VrlNull{})
		}
		'match' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('match requires value argument') }
			pattern := if v := named['pattern'] { v } else if pos.len > 1 { pos[1] } else { return error('match requires pattern argument') }
			return fn_match([value, pattern])
		}
		'match_any' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('match_any requires value argument') }
			patterns := if v := named['patterns'] { v } else if pos.len > 1 { pos[1] } else { return error('match_any requires patterns argument') }
			return fn_match_any([value, patterns])
		}
		'includes' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('includes requires value argument') }
			item := if v := named['item'] { v } else if pos.len > 1 { pos[1] } else { return error('includes requires item argument') }
			return fn_includes([value, item])
		}
		'unique' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('unique requires value argument') }
			return fn_unique([value])
		}
		'encode_base64' {
			if pos.len < 1 { return error('encode_base64 requires 1 argument') }
			padding := VrlValue(get_named_bool(named, 'padding', true))
			charset := VrlValue(get_named_string(named, 'charset', 'standard'))
			return fn_encode_base64([pos[0], padding, charset])
		}
		'decode_base64' {
			if pos.len < 1 { return error('decode_base64 requires 1 argument') }
			charset := VrlValue(get_named_string(named, 'charset', 'standard'))
			return fn_decode_base64([pos[0], charset])
		}
		'encode_percent' {
			if pos.len < 1 { return error('encode_percent requires 1 argument') }
			ascii_set := VrlValue(get_named_string(named, 'ascii_set', 'NON_ALPHANUMERIC'))
			return fn_encode_percent([pos[0], ascii_set])
		}
		'encode_key_value' {
			if pos.len < 1 { return error('encode_key_value requires 1 argument') }
			fields_ordering := if v := named['fields_ordering'] { v } else { VrlValue([]VrlValue{}) }
			kv_delim := VrlValue(get_named_string(named, 'key_value_delimiter', '='))
			field_delim := VrlValue(get_named_string(named, 'field_delimiter', ' '))
			flatten_bool := VrlValue(get_named_bool(named, 'flatten_boolean', false))
			return fn_encode_key_value([pos[0], fields_ordering, kv_delim, field_delim, flatten_bool])
		}
		'encode_csv' {
			if pos.len < 1 { return error('encode_csv requires 1 argument') }
			delimiter := VrlValue(get_named_string(named, 'delimiter', ','))
			return fn_encode_csv([pos[0], delimiter])
		}
		'parse_key_value' {
			if pos.len < 1 { return error('parse_key_value requires 1 argument') }
			kv_delim := VrlValue(get_named_string(named, 'key_value_delimiter', '='))
			field_delim := VrlValue(get_named_string(named, 'field_delimiter', ' '))
			whitespace := VrlValue(get_named_string(named, 'whitespace', 'lenient'))
			accept_standalone := VrlValue(get_named_bool(named, 'accept_standalone_key', true))
			return fn_parse_key_value([pos[0], kv_delim, field_delim, whitespace, accept_standalone])
		}
		'parse_csv' {
			if pos.len < 1 { return error('parse_csv requires 1 argument') }
			delimiter := VrlValue(get_named_string(named, 'delimiter', ','))
			return fn_parse_csv([pos[0], delimiter])
		}
		'parse_duration' {
			if pos.len < 1 { return error('parse_duration requires 1 argument') }
			unit := if v := named['unit'] { v } else if pos.len > 1 { pos[1] } else { return error('parse_duration requires unit') }
			return fn_parse_duration([pos[0], unit])
		}
		'parse_bytes' {
			if pos.len < 1 { return error('parse_bytes requires 1 argument') }
			unit := if v := named['unit'] { v } else if pos.len > 1 { pos[1] } else { VrlValue('b') }
			base := if v := named['base'] { v } else if pos.len > 2 { pos[2] } else { VrlValue('2') }
			return fn_parse_bytes([pos[0], unit, base])
		}
		'parse_timestamp' {
			if pos.len < 1 { return error('parse_timestamp requires 1 argument') }
			format := if v := named['format'] { v } else if pos.len > 1 { pos[1] } else { return error('parse_timestamp requires format') }
			return fn_parse_timestamp([pos[0], format])
		}
		'format_timestamp' {
			if pos.len < 1 { return error('format_timestamp requires 1 argument') }
			format := if v := named['format'] { v } else if pos.len > 1 { pos[1] } else { return error('format_timestamp requires format') }
			tz_val := if v := named['timezone'] { v } else if pos.len > 2 { pos[2] } else { VrlValue('UTC') }
			return fn_format_timestamp([pos[0], format, tz_val])
		}
		'sha2' {
			if pos.len < 1 { return error('sha2 requires 1 argument') }
			variant := if v := named['variant'] { v } else if pos.len > 1 { pos[1] } else { VrlValue('SHA-512/256') }
			return fn_sha2([pos[0], variant])
		}
		'hmac' {
			if pos.len < 2 { return error('hmac requires 2 arguments') }
			algo := if v := named['algorithm'] { v } else if pos.len > 2 { pos[2] } else { VrlValue('SHA-256') }
			return fn_hmac([pos[0], pos[1], algo])
		}
		'sieve' {
			if pos.len < 1 { return error('sieve requires at least 1 argument') }
			pattern_val := if v := named['permitted_characters'] { v } else if pos.len > 1 { pos[1] } else { return error('sieve requires a pattern') }
			replace_single := VrlValue(get_named_string(named, 'replace_single', ''))
			replace_repeated := VrlValue(get_named_string(named, 'replace_repeated', ''))
			return fn_sieve([pos[0], pattern_val, replace_single, replace_repeated])
		}
		'shannon_entropy' {
			if pos.len < 1 { return error('shannon_entropy requires 1 argument') }
			seg := VrlValue(get_named_string(named, 'segmentation', 'byte'))
			return fn_shannon_entropy([pos[0], seg])
		}
		'chunks' {
			if pos.len < 2 { return error('chunks requires 2 arguments') }
			return fn_chunks(pos)
		}
		'match_array' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('match_array requires value') }
			pattern := if v := named['pattern'] { v } else if pos.len > 1 { pos[1] } else { return error('match_array requires pattern') }
			all := VrlValue(get_named_bool(named, 'all', false))
			return fn_match_array([value, pattern, all])
		}
		'parse_regex' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('parse_regex requires value') }
			pattern := if v := named['pattern'] { v } else if pos.len > 1 { pos[1] } else { return error('parse_regex requires pattern') }
			ng := VrlValue(get_named_bool(named, 'numeric_groups', false))
			return fn_parse_regex([value, pattern, ng])
		}
		'parse_regex_all' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('parse_regex_all requires value') }
			pattern := if v := named['pattern'] { v } else if pos.len > 1 { pos[1] } else { return error('parse_regex_all requires pattern') }
			ng := VrlValue(get_named_bool(named, 'numeric_groups', false))
			return fn_parse_regex_all([value, pattern, ng])
		}
		'ip_cidr_contains' {
			cidr := if v := named['cidr'] { v } else if pos.len > 0 { pos[0] } else { return error('ip_cidr_contains requires cidr') }
			ip := if v := named['ip'] { v } else if pos.len > 1 { pos[1] } else { return error('ip_cidr_contains requires ip') }
			return fn_ip_cidr_contains([cidr, ip])
		}
		'parse_url' {
			if pos.len < 1 { return error('parse_url requires 1 argument') }
			return fn_parse_url(pos)
		}
		'parse_query_string' {
			if pos.len < 1 { return error('parse_query_string requires 1 argument') }
			return fn_parse_query_string(pos)
		}
		'basename' {
			if pos.len < 1 { return error('basename requires 1 argument') }
			return fn_basename(pos)
		}
		'remove' {
			value := if v := named['value'] { v } else if pos.len > 0 { pos[0] } else { return error('remove requires value') }
			path := if v := named['path'] { v } else if pos.len > 1 { pos[1] } else { return error('remove requires path') }
			compact := VrlValue(get_named_bool(named, 'compact', false))
			return fn_remove([value, path, compact])
		}
		'object_from_array' {
			values := if v := named['values'] { v } else if pos.len > 0 { pos[0] } else { return error('object_from_array requires values') }
			if keys := named['keys'] {
				return fn_object_from_array([values, keys])
			}
			return fn_object_from_array([values])
		}
		'tag_types_externally' {
			if pos.len < 1 { return error('tag_types_externally requires 1 argument') }
			return fn_tag_types_externally(pos)
		}
		'uuid_v7' {
			return fn_uuid_v7(pos)
		}
		'haversine' {
			if pos.len < 4 { return error('haversine requires 4 arguments') }
			unit := VrlValue(get_named_string(named, 'measurement_unit', 'kilometers'))
			return fn_haversine([pos[0], pos[1], pos[2], pos[3], unit])
		}
		else {
			// Fallback: pass all positional args to the general dispatch
			mut all_args := pos.clone()
			for _, v in named {
				all_args << v
			}
			return rt.eval_fn_call_positional(name, all_args)
		}
	}
}

fn (mut rt Runtime) eval_fn_call_positional(name string, args []VrlValue) !VrlValue {
	match name {
		'to_string' { return fn_to_string(args) }
		'downcase' { return fn_downcase(args) }
		'upcase' { return fn_upcase(args) }
		'contains' { return fn_contains(args) }
		'starts_with' { return fn_starts_with(args) }
		'ends_with' { return fn_ends_with(args) }
		'length' { return fn_length(args) }
		'strip_whitespace', 'trim' { return fn_strip_whitespace(args) }
		'replace' { return fn_replace(args) }
		'slice' { return fn_slice(args) }
		'split' { return fn_split(args) }
		'join' { return fn_join(args) }
		'strlen' { return fn_strlen(args) }
		'truncate' { return fn_truncate(args) }
		'to_int', 'int' { return fn_to_int(args) }
		'to_float', 'float' { return fn_to_float(args) }
		'to_bool', 'bool' { return fn_to_bool(args) }
		'string' { return fn_string(args) }
		'is_nullish' { return fn_is_nullish(args) }
		'is_string' { return fn_is_type(args, 'string') }
		'is_integer' { return fn_is_type(args, 'integer') }
		'is_float' { return fn_is_type(args, 'float') }
		'is_boolean' { return fn_is_type(args, 'boolean') }
		'is_null' { return fn_is_type(args, 'null') }
		'is_array' { return fn_is_type(args, 'array') }
		'is_object' { return fn_is_type(args, 'object') }
		'keys' { return fn_keys(args) }
		'values' { return fn_values(args) }
		'flatten' { return fn_flatten(args) }
		'unflatten' { return fn_unflatten(args) }
		'merge' { return fn_merge(args) }
		'compact' { return fn_compact(args) }
		'push' { return fn_push(args) }
		'append' { return fn_append(args) }
		'encode_json' { return fn_encode_json(args) }
		'decode_json', 'parse_json' { return fn_decode_json(args) }
		'abs' { return fn_abs(args) }
		'ceil' { return fn_ceil(args) }
		'floor' { return fn_floor(args) }
		'round' { return fn_round(args) }
		'mod' { return fn_mod(args) }
		'format_number' { return fn_format_number(args) }
		'match' { return fn_match(args) }
		'match_any' { return fn_match_any(args) }
		'includes' { return fn_includes(args) }
		'contains_all' { return fn_contains_all(args) }
		'find' { return fn_find(args) }
		'get' { return fn_get(args) }
		'set' { return fn_set(args) }
		'unique' { return fn_unique(args) }
		'pop' { return fn_pop(args) }
		'to_regex' { return fn_to_regex(args) }
		'from_unix_timestamp' { return fn_from_unix_timestamp(args) }
		'to_unix_timestamp' { return fn_to_unix_timestamp(args) }
		'assert' { return fn_assert(args) }
		'assert_eq' { return fn_assert_eq(args) }
		'array' { return fn_ensure_array(args) }
		'object' { return fn_ensure_object(args) }
		'log' { return VrlValue(VrlNull{}) }
		'now' { return VrlValue(Timestamp{t: time.now()}) }
		'uuid_v4' { return fn_uuid_v4() }
		'get_env_var' { return fn_get_env_var(args) }
		// Codec
		'encode_base64' { return fn_encode_base64(args) }
		'decode_base64' { return fn_decode_base64(args) }
		'encode_base16' { return fn_encode_base16(args) }
		'decode_base16' { return fn_decode_base16(args) }
		'encode_percent' { return fn_encode_percent(args) }
		'decode_percent' { return fn_decode_percent(args) }
		'encode_csv' { return fn_encode_csv(args) }
		'encode_key_value' { return fn_encode_key_value(args) }
		'encode_logfmt' { return fn_encode_logfmt(args) }
		'decode_mime_q' { return fn_decode_mime_q(args) }
		'encode_zlib' { return fn_encode_zlib(args) }
		'decode_zlib' { return fn_decode_zlib(args) }
		'encode_gzip' { return fn_encode_gzip(args) }
		'decode_gzip' { return fn_decode_gzip(args) }
		'encode_zstd' { return fn_encode_zstd(args) }
		'decode_zstd' { return fn_decode_zstd(args) }
		// Crypto
		'sha1' { return fn_sha1(args) }
		'sha2' { return fn_sha2(args) }
		'sha3' { return fn_sha3(args) }
		'md5' { return fn_md5(args) }
		'hmac' { return fn_hmac(args) }
		'crc32' { return fn_crc32(args) }
		// String
		'camelcase' { return fn_camelcase(args) }
		'pascalcase' { return fn_pascalcase(args) }
		'snakecase' { return fn_snakecase(args) }
		'kebabcase' { return fn_kebabcase(args) }
		'screamingsnakecase' { return fn_screamingsnakecase(args) }
		'basename' { return fn_basename(args) }
		'dirname' { return fn_dirname(args) }
		'split_path' { return fn_split_path(args) }
		'strip_ansi_escape_codes' { return fn_strip_ansi_escape_codes(args) }
		'shannon_entropy' { return fn_shannon_entropy(args) }
		'sieve' { return fn_sieve(args) }
		// Parse
		'parse_regex' { return fn_parse_regex(args) }
		'parse_regex_all' { return fn_parse_regex_all(args) }
		'parse_key_value' { return fn_parse_key_value(args) }
		'parse_logfmt' { return fn_parse_logfmt(args) }
		'parse_klog' { return fn_parse_klog(args) }
		'parse_linux_authorization' { return fn_parse_linux_authorization(args) }
		'parse_csv' { return fn_parse_csv(args) }
		'parse_url' { return fn_parse_url(args) }
		'parse_query_string' { return fn_parse_query_string(args) }
		'parse_tokens' { return fn_parse_tokens(args) }
		'parse_common_log' { return fn_parse_common_log(args) }
		'parse_yaml' { return fn_parse_yaml(args) }
		'parse_syslog' { return fn_parse_syslog(args) }
		'parse_duration' { return fn_parse_duration(args) }
		'parse_bytes' { return fn_parse_bytes(args) }
		'parse_int' { return fn_parse_int(args) }
		'parse_float' { return fn_parse_float(args) }
		'format_int' { return fn_format_int(args) }
		'parse_timestamp' { return fn_parse_timestamp(args) }
		'format_timestamp' { return fn_format_timestamp(args) }
		// Type
		'is_empty' { return fn_is_empty(args) }
		'is_json' { return fn_is_json(args) }
		'is_regex' { return fn_is_regex(args) }
		'is_timestamp' { return fn_is_timestamp(args) }
		'is_ipv4' { return fn_is_ipv4(args) }
		'is_ipv6' { return fn_is_ipv6(args) }
		'timestamp' { return fn_timestamp(args) }
		'tag_types_externally' { return fn_tag_types_externally(args) }
		// Enumerate
		'tally' { return fn_tally(args) }
		'tally_value' { return fn_tally_value(args) }
		'match_array' { return fn_match_array(args) }
		// IP
		'ip_aton' { return fn_ip_aton(args) }
		'ip_ntoa' { return fn_ip_ntoa(args) }
		'ip_cidr_contains' { return fn_ip_cidr_contains(args) }
		'ip_subnet' { return fn_ip_subnet(args) }
		'ip_to_ipv6' { return fn_ip_to_ipv6(args) }
		'ipv6_to_ipv4' { return fn_ipv6_to_ipv4(args) }
		'ip_version' { return fn_ip_version(args) }
		// Convert
		'to_syslog_level' { return fn_to_syslog_level(args) }
		'to_syslog_severity' { return fn_to_syslog_severity(args) }
		'to_syslog_facility' { return fn_to_syslog_facility(args) }
		'to_syslog_facility_code' { return fn_to_syslog_facility_code(args) }
		// Object
		'unnest' { return fn_unnest(args) }
		'object_from_array' { return fn_object_from_array(args) }
		'zip' { return fn_zip(args) }
		'remove' { return fn_remove(args) }
		// Array
		'chunks' { return fn_chunks(args) }
		// Random
		'random_int' { return fn_random_int(args) }
		'random_float' { return fn_random_float(args) }
		'random_bool' { return fn_random_bool() }
		'random_bytes' { return fn_random_bytes(args) }
		'uuid_v7' { return fn_uuid_v7(args) }
		'get_hostname' { return fn_get_hostname() }
		'get_timezone_name' { return fn_get_timezone_name(args) }
		'haversine' { return fn_haversine(args) }
		else { return error('unknown function: ${name}') }
	}
}

fn fn_compact_named(v VrlValue, named map[string]VrlValue) !VrlValue {
	null_flag := get_named_bool(named, 'null', true)
	string_flag := get_named_bool(named, 'string', true)
	object_flag := get_named_bool(named, 'object', true)
	array_flag := get_named_bool(named, 'array', true)
	nullish_flag := get_named_bool(named, 'nullish', false)
	recursive := get_named_bool(named, 'recursive', true)
	return compact_value(v, null_flag, string_flag, object_flag, array_flag, nullish_flag, recursive)
}

// fn_max_args returns the max number of positional args a function accepts, or -1 if unknown.
fn fn_max_args(name string) int {
	return match name {
		// Strict 1-arg functions (no optional parameters)
		'to_string', 'to_int', 'int', 'to_float', 'float', 'to_bool', 'bool',
		'string', 'length', 'strlen', 'strip_whitespace', 'trim', 'downcase', 'upcase',
		'is_string', 'is_integer', 'is_float', 'is_boolean', 'is_null', 'is_array', 'is_object',
		'is_nullish', 'is_empty', 'is_json', 'is_regex', 'is_timestamp', 'is_ipv4', 'is_ipv6',
		'keys', 'values',
		'abs', 'array', 'object', 'timestamp',
		'decode_mime_q', 'sha1', 'md5',
		'tag_types_externally', 'tally',
		'ip_version', 'type_def', 'pop',
		'decode_zlib', 'decode_gzip', 'decode_zstd' { 1 }
		else { -1 }
	}
}

// fn_valid_keywords returns the valid named argument keywords for a function.
fn fn_valid_keywords(name string) []string {
	return match name {
		'to_string' { ['value'] }
		'to_int' { ['value'] }
		'to_float' { ['value'] }
		'to_bool' { ['value'] }
		'downcase', 'upcase' { ['value'] }
		'contains' { ['value', 'substring', 'case_sensitive'] }
		'starts_with' { ['value', 'substring', 'case_sensitive'] }
		'ends_with' { ['value', 'substring', 'case_sensitive'] }
		'split' { ['value', 'pattern', 'limit'] }
		'join' { ['value', 'separator'] }
		'replace' { ['value', 'pattern', 'with', 'count'] }
		'truncate' { ['value', 'limit', 'ellipsis', 'suffix'] }
		'slice' { ['value', 'start', 'end'] }
		'match' { ['value', 'pattern'] }
		'match_any' { ['value', 'patterns'] }
		'parse_regex' { ['value', 'pattern', 'numeric_groups'] }
		'parse_regex_all' { ['value', 'pattern', 'numeric_groups'] }
		'parse_key_value' { ['value', 'key_value_delimiter', 'field_delimiter', 'whitespace', 'accept_standalone_key'] }
		'format_timestamp' { ['value', 'format', 'timezone'] }
		'parse_timestamp' { ['value', 'format', 'timezone'] }
		'to_unix_timestamp' { ['value', 'unit'] }
		'from_unix_timestamp' { ['value', 'unit'] }
		'encode_base64' { ['value', 'padding', 'charset'] }
		'sha2' { ['value', 'variant'] }
		'hmac' { ['value', 'key', 'algorithm'] }
		'round' { ['value', 'precision'] }
		'format_number' { ['value', 'decimal_separator', 'grouping_separator', 'fractional_digits'] }
		'compact' { ['value', 'null', 'string', 'object', 'array', 'nullish', 'recursive'] }
		'merge' { ['value', 'other', 'deep'] }
		'find' { ['value', 'pattern', 'from'] }
		'set' { ['value', 'path', 'data'] }
		'get' { ['value', 'path'] }
		'remove' { ['value', 'path', 'compact'] }
		'chunks' { ['value', 'chunk_size'] }
		'parse_csv' { ['value', 'delimiter'] }
		'encode_csv' { ['value', 'delimiter'] }
		'encode_key_value' { ['value', 'fields_ordering', 'key_value_delimiter', 'field_delimiter'] }
		'ip_subnet' { ['value', 'subnet'] }
		'uuid_v7' { ['timestamp'] }
		'random_bytes' { ['length'] }
		'parse_duration' { ['value', 'unit'] }
		'sieve' { ['value', 'pattern', 'replace_single', 'replace_repeated', 'permitted_characters'] }
		'assert' { ['condition', 'message'] }
		'assert_eq' { ['left', 'right', 'message'] }
		'log' { ['value', 'level', 'rate_limit_secs'] }
		else { []string{} }
	}
}

// validate_fn_args checks if a function call has too many arguments.
fn validate_fn_args(name string, expr FnCallExpr) ! {
	max := fn_max_args(name)
	if max < 0 { return }
	// Count positional args (excluding named args)
	mut positional := 0
	for i in 0 .. expr.args.len {
		if i >= expr.arg_names.len || expr.arg_names[i].len == 0 {
			positional++
		}
	}
	if expr.args.len > max {
		return error('too many function arguments: ${name} takes a maximum of ${max} argument${if max != 1 { 's' } else { '' }}')
	}
}

// validate_fn_keywords checks if named argument keywords are valid for the function.
fn validate_fn_keywords(name string, expr FnCallExpr) ! {
	valid := fn_valid_keywords(name)
	if valid.len == 0 { return }
	for i, arg_name in expr.arg_names {
		if arg_name.len > 0 && arg_name !in valid {
			return error('unknown keyword argument "${arg_name}" for function "${name}"')
		}
	}
}

// eval_fn_call dispatches built-in VRL functions.
fn (mut rt Runtime) eval_fn_call(expr FnCallExpr) !VrlValue {
	// Strip trailing '!' more efficiently using byte check
	mut name := expr.name
	if name.len > 0 && name[name.len - 1] == `!` {
		name = name[..name.len - 1]
	}

	// Validate function argument count
	validate_fn_args(name, expr)!

	// Validate named argument keywords
	validate_fn_keywords(name, expr)!

	// Special functions that need unevaluated args (PathExpr)
	if name == 'del' { return rt.fn_del(expr) }
	if name == 'exists' { return rt.fn_exists(expr) }
	if name == 'type_def' { return rt.fn_type_def_static(expr) }
	if name == 'filter' { return rt.fn_filter(expr) }
	if name == 'for_each' { return rt.fn_for_each(expr) }
	if name == 'map_keys' { return rt.fn_map_keys(expr) }
	if name == 'map_values' { return rt.fn_map_values(expr) }
	if name == 'replace_with' { return rt.fn_replace_with(expr) }
	if name == 'unnest' { return rt.fn_unnest_special(expr) }

	// If any args are named, use named-arg dispatch
	has_named := expr.arg_names.len > 0 && expr.arg_names.any(it.len > 0)
	if has_named {
		return rt.eval_fn_call_named(name, expr)
	}

	// Fast path for common 1-arg functions: evaluate arg directly without []VrlValue alloc
	if expr.args.len == 1 {
		a0 := rt.eval(expr.args[0])!
		match name {
			'downcase' {
				v := a0
				match v {
					string { return VrlValue(v.to_lower()) }
					else { return error('downcase requires a string argument') }
				}
			}
			'upcase' {
				v := a0
				match v {
					string { return VrlValue(v.to_upper()) }
					else { return error('upcase requires a string argument') }
				}
			}
			'to_string' { return fn_to_string([a0]) }
		'format_number' { return fn_format_number([a0]) }
			'to_int', 'int' { return fn_to_int([a0]) }
			'to_float', 'float' { return fn_to_float([a0]) }
			'to_bool', 'bool' { return fn_to_bool([a0]) }
			'string' { return fn_string([a0]) }
			'length' { return fn_length([a0]) }
			'strlen' { return fn_strlen([a0]) }
			'strip_whitespace', 'trim' { return fn_strip_whitespace([a0]) }
			'is_string' { return VrlValue(a0 is string) }
			'is_integer' { return VrlValue(a0 is i64) }
			'is_float' { return VrlValue(a0 is f64) }
			'is_boolean' { return VrlValue(a0 is bool) }
			'is_null' { return VrlValue(a0 is VrlNull) }
			'is_array' { return VrlValue(a0 is []VrlValue) }
			'is_object' { return VrlValue(a0 is ObjectMap) }
			'is_nullish' { return fn_is_nullish([a0]) }
			'encode_json' { return fn_encode_json([a0]) }
			'decode_json', 'parse_json' { return fn_decode_json([a0]) }
			'keys' { return fn_keys([a0]) }
			'values' { return fn_values([a0]) }
			'flatten' { return fn_flatten([a0]) }
			'unflatten' { return fn_unflatten([a0]) }
			'compact' { return fn_compact([a0]) }
			'abs' { return fn_abs([a0]) }
			'ceil' { return fn_ceil([a0]) }
			'floor' { return fn_floor([a0]) }
			'round' { return fn_round([a0]) }
			'array' { return fn_ensure_array([a0]) }
			'object' { return fn_ensure_object([a0]) }
			'is_empty' { return fn_is_empty([a0]) }
			'is_regex' { return fn_is_regex([a0]) }
			'is_timestamp' { return fn_is_timestamp([a0]) }
			'timestamp' { return fn_timestamp([a0]) }
			'camelcase' { return fn_camelcase([a0]) }
			'pascalcase' { return fn_pascalcase([a0]) }
			'snakecase' { return fn_snakecase([a0]) }
			'kebabcase' { return fn_kebabcase([a0]) }
			'screamingsnakecase' { return fn_screamingsnakecase([a0]) }
			'basename' { return fn_basename([a0]) }
			'dirname' { return fn_dirname([a0]) }
			'split_path' { return fn_split_path([a0]) }
			'strip_ansi_escape_codes' { return fn_strip_ansi_escape_codes([a0]) }
			'encode_base64' { return fn_encode_base64([a0]) }
			'decode_base64' { return fn_decode_base64([a0]) }
			'encode_base16' { return fn_encode_base16([a0]) }
			'decode_base16' { return fn_decode_base16([a0]) }
			'encode_percent' { return fn_encode_percent([a0]) }
			'decode_percent' { return fn_decode_percent([a0]) }
			'encode_logfmt' { return fn_encode_logfmt([a0]) }
			'encode_csv' { return fn_encode_csv([a0]) }
			'decode_mime_q' { return fn_decode_mime_q([a0]) }
			'encode_zlib' { return fn_encode_zlib([a0]) }
			'decode_zlib' { return fn_decode_zlib([a0]) }
			'encode_gzip' { return fn_encode_gzip([a0]) }
			'decode_gzip' { return fn_decode_gzip([a0]) }
			'encode_zstd' { return fn_encode_zstd([a0]) }
			'decode_zstd' { return fn_decode_zstd([a0]) }
			'sha1' { return fn_sha1([a0]) }
			'md5' { return fn_md5([a0]) }
			'crc32' { return fn_crc32([a0]) }
			'parse_float' { return fn_parse_float([a0]) }
			'tag_types_externally' { return fn_tag_types_externally([a0]) }
			'tally' { return fn_tally([a0]) }
			'tally_value' { return fn_tally_value([a0]) }
			'parse_tokens' { return fn_parse_tokens([a0]) }
			'parse_common_log' { return fn_parse_common_log([a0]) }
			'parse_yaml' { return fn_parse_yaml([a0]) }
			'parse_syslog' { return fn_parse_syslog([a0]) }
			'parse_logfmt' { return fn_parse_logfmt([a0]) }
			'parse_klog' { return fn_parse_klog([a0]) }
			'parse_linux_authorization' { return fn_parse_linux_authorization([a0]) }
			'get_timezone_name' { return fn_get_timezone_name([a0]) }
			'parse_url' { return fn_parse_url([a0]) }
			'parse_query_string' { return fn_parse_query_string([a0]) }
			'parse_bytes' { return fn_parse_bytes([a0]) }
			'unnest' { return fn_unnest([a0]) }
			'is_ipv4' { return fn_is_ipv4([a0]) }
			'is_ipv6' { return fn_is_ipv6([a0]) }
			'ip_version' { return fn_ip_version([a0]) }
			// map_keys and map_values are handled above as special functions
			else {}
		}
		// Fall through to 2-arg path or general path
	}

	// Fast path for common 2-arg functions
	if expr.args.len == 2 {
		a0 := if expr.args.len >= 1 { rt.eval(expr.args[0])! } else { VrlValue(VrlNull{}) }
		a1 := rt.eval(expr.args[1])!
		match name {
			'contains' { return fn_contains([a0, a1]) }
			'starts_with' { return fn_starts_with([a0, a1]) }
			'ends_with' { return fn_ends_with([a0, a1]) }
			'split' { return fn_split([a0, a1]) }
			'join' { return fn_join([a0, a1]) }
			'merge' { return fn_merge([a0, a1]) }
			'push' { return fn_push([a0, a1]) }
			'append' { return fn_append([a0, a1]) }
			'mod' { return fn_mod([a0, a1]) }
			'slice' { return fn_slice([a0, a1]) }
			'truncate' { return fn_truncate([a0, a1]) }
			'encode_zlib' { return fn_encode_zlib([a0, a1]) }
			'encode_gzip' { return fn_encode_gzip([a0, a1]) }
			'encode_zstd' { return fn_encode_zstd([a0, a1]) }
			else {}
		}
	}

	// General path: evaluate all args into array
	mut args := []VrlValue{}
	for arg in expr.args {
		val := rt.eval(arg)!
		args << val
	}

	match name {
		'to_string' { return fn_to_string(args) }
		'downcase' { return fn_downcase(args) }
		'upcase' { return fn_upcase(args) }
		'contains' { return fn_contains(args) }
		'starts_with' { return fn_starts_with(args) }
		'ends_with' { return fn_ends_with(args) }
		'length' { return fn_length(args) }
		'strip_whitespace', 'trim' { return fn_strip_whitespace(args) }
		'replace' { return fn_replace(args) }
		'slice' { return fn_slice(args) }
		'split' { return fn_split(args) }
		'join' { return fn_join(args) }
		'strlen' { return fn_strlen(args) }
		'truncate' { return fn_truncate(args) }
		'to_int', 'int' { return fn_to_int(args) }
		'to_float', 'float' { return fn_to_float(args) }
		'to_bool', 'bool' { return fn_to_bool(args) }
		'string' { return fn_string(args) }
		'is_string' { return fn_is_type(args, 'string') }
		'is_integer' { return fn_is_type(args, 'integer') }
		'is_float' { return fn_is_type(args, 'float') }
		'is_boolean' { return fn_is_type(args, 'boolean') }
		'is_null' { return fn_is_type(args, 'null') }
		'is_array' { return fn_is_type(args, 'array') }
		'is_object' { return fn_is_type(args, 'object') }
		'is_nullish' { return fn_is_nullish(args) }
		'keys' { return fn_keys(args) }
		'values' { return fn_values(args) }
		'flatten' { return fn_flatten(args) }
		'unflatten' { return fn_unflatten(args) }
		'merge' { return fn_merge(args) }
		'compact' { return fn_compact(args) }
		'push' { return fn_push(args) }
		'append' { return fn_append(args) }
		// map_keys and map_values handled as special functions above
		'encode_json' { return fn_encode_json(args) }
		'decode_json', 'parse_json' { return fn_decode_json(args) }
		'abs' { return fn_abs(args) }
		'ceil' { return fn_ceil(args) }
		'floor' { return fn_floor(args) }
		'round' { return fn_round(args) }
		'mod' { return fn_mod(args) }
		'assert' { return fn_assert(args) }
		'assert_eq' { return fn_assert_eq(args) }
		'now' { return VrlValue(Timestamp{t: time.now()}) }
		'format_number' { return fn_format_number(args) }
		'to_unix_timestamp' { return fn_to_unix_timestamp(args) }
		'get_env_var' { return fn_get_env_var(args) }
		'uuid_v4' { return fn_uuid_v4() }
		'array' { return fn_ensure_array(args) }
		'object' { return fn_ensure_object(args) }
		'pop' { return fn_pop(args) }
		'match' { return fn_match(args) }
		'match_any' { return fn_match_any(args) }
		'includes' { return fn_includes(args) }
		'contains_all' { return fn_contains_all(args) }
		'find' { return fn_find(args) }
		'get' { return fn_get(args) }
		'set' { return fn_set(args) }
		'unique' { return fn_unique(args) }
		'to_regex' { return fn_to_regex(args) }
		'log' { return VrlValue(VrlNull{}) }  // log() is a no-op in our runtime
		'from_unix_timestamp' { return fn_from_unix_timestamp(args) }
		// Codec
		'encode_base64' { return fn_encode_base64(args) }
		'decode_base64' { return fn_decode_base64(args) }
		'encode_base16' { return fn_encode_base16(args) }
		'decode_base16' { return fn_decode_base16(args) }
		'encode_percent' { return fn_encode_percent(args) }
		'decode_percent' { return fn_decode_percent(args) }
		'encode_csv' { return fn_encode_csv(args) }
		'encode_key_value' { return fn_encode_key_value(args) }
		'encode_logfmt' { return fn_encode_logfmt(args) }
		'decode_mime_q' { return fn_decode_mime_q(args) }
		'encode_zlib' { return fn_encode_zlib(args) }
		'decode_zlib' { return fn_decode_zlib(args) }
		'encode_gzip' { return fn_encode_gzip(args) }
		'decode_gzip' { return fn_decode_gzip(args) }
		'encode_zstd' { return fn_encode_zstd(args) }
		'decode_zstd' { return fn_decode_zstd(args) }
		// Crypto
		'sha1' { return fn_sha1(args) }
		'sha2' { return fn_sha2(args) }
		'sha3' { return fn_sha3(args) }
		'md5' { return fn_md5(args) }
		'hmac' { return fn_hmac(args) }
		'crc32' { return fn_crc32(args) }
		// String
		'camelcase' { return fn_camelcase(args) }
		'pascalcase' { return fn_pascalcase(args) }
		'snakecase' { return fn_snakecase(args) }
		'kebabcase' { return fn_kebabcase(args) }
		'screamingsnakecase' { return fn_screamingsnakecase(args) }
		'basename' { return fn_basename(args) }
		'dirname' { return fn_dirname(args) }
		'split_path' { return fn_split_path(args) }
		'strip_ansi_escape_codes' { return fn_strip_ansi_escape_codes(args) }
		'shannon_entropy' { return fn_shannon_entropy(args) }
		'sieve' { return fn_sieve(args) }
		// Parse
		'parse_regex' { return fn_parse_regex(args) }
		'parse_regex_all' { return fn_parse_regex_all(args) }
		'parse_key_value' { return fn_parse_key_value(args) }
		'parse_logfmt' { return fn_parse_logfmt(args) }
		'parse_klog' { return fn_parse_klog(args) }
		'parse_linux_authorization' { return fn_parse_linux_authorization(args) }
		'parse_csv' { return fn_parse_csv(args) }
		'parse_url' { return fn_parse_url(args) }
		'parse_query_string' { return fn_parse_query_string(args) }
		'parse_tokens' { return fn_parse_tokens(args) }
		'parse_common_log' { return fn_parse_common_log(args) }
		'parse_yaml' { return fn_parse_yaml(args) }
		'parse_syslog' { return fn_parse_syslog(args) }
		'parse_duration' { return fn_parse_duration(args) }
		'parse_bytes' { return fn_parse_bytes(args) }
		'parse_int' { return fn_parse_int(args) }
		'parse_float' { return fn_parse_float(args) }
		'format_int' { return fn_format_int(args) }
		'parse_timestamp' { return fn_parse_timestamp(args) }
		'format_timestamp' { return fn_format_timestamp(args) }
		// Type
		'is_empty' { return fn_is_empty(args) }
		'is_json' { return fn_is_json(args) }
		'is_regex' { return fn_is_regex(args) }
		'is_timestamp' { return fn_is_timestamp(args) }
		'is_ipv4' { return fn_is_ipv4(args) }
		'is_ipv6' { return fn_is_ipv6(args) }
		'timestamp' { return fn_timestamp(args) }
		'tag_types_externally' { return fn_tag_types_externally(args) }
		// Enumerate
		'tally' { return fn_tally(args) }
		'tally_value' { return fn_tally_value(args) }
		'match_array' { return fn_match_array(args) }
		// IP
		'ip_aton' { return fn_ip_aton(args) }
		'ip_ntoa' { return fn_ip_ntoa(args) }
		'ip_cidr_contains' { return fn_ip_cidr_contains(args) }
		'ip_subnet' { return fn_ip_subnet(args) }
		'ip_to_ipv6' { return fn_ip_to_ipv6(args) }
		'ipv6_to_ipv4' { return fn_ipv6_to_ipv4(args) }
		'ip_version' { return fn_ip_version(args) }
		// Convert
		'to_syslog_level' { return fn_to_syslog_level(args) }
		'to_syslog_severity' { return fn_to_syslog_severity(args) }
		'to_syslog_facility' { return fn_to_syslog_facility(args) }
		'to_syslog_facility_code' { return fn_to_syslog_facility_code(args) }
		// Object
		'unnest' { return fn_unnest(args) }
		'object_from_array' { return fn_object_from_array(args) }
		'zip' { return fn_zip(args) }
		'remove' { return fn_remove(args) }
		// Array
		'chunks' { return fn_chunks(args) }
		// Random
		'random_int' { return fn_random_int(args) }
		'random_float' { return fn_random_float(args) }
		'random_bool' { return fn_random_bool() }
		'random_bytes' { return fn_random_bytes(args) }
		'uuid_v7' { return fn_uuid_v7(args) }
		'get_hostname' { return fn_get_hostname() }
		'get_timezone_name' { return fn_get_timezone_name(args) }
		'haversine' { return fn_haversine(args) }
		else { return error('unknown function: ${name}') }
	}
}

// String functions
fn fn_to_string(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_string requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a) }
		i64 { return VrlValue('${a}') }
		f64 { return VrlValue(format_float(a)) }
		bool {
			s := if a { 'true' } else { 'false' }
			return VrlValue(s)
		}
		VrlNull { return VrlValue('') }
		Timestamp {
			s := format_timestamp(a.t)
			return VrlValue(s)
		}
		else { return error('expected string, got ${vrl_type_name(a)}') }
	}
}

fn fn_downcase(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('downcase requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.to_lower()) }
		else { return error('downcase requires a string argument') }
	}
}

fn fn_upcase(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('upcase requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.to_upper()) }
		else { return error('upcase requires a string argument') }
	}
}

fn fn_contains(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('contains requires 2 arguments') }
	a := args[0]
	b := args[1]
	case_sensitive := if args.len > 2 { get_bool_arg(args[2], true) } else { true }
	match a {
		string {
			match b {
				string {
					if case_sensitive {
						return VrlValue(a.contains(b))
					}
					return VrlValue(a.to_lower().contains(b.to_lower()))
				}
				else { return error('invalid argument type') }
			}
		}
		else { return error('invalid argument type') }
	}
}

fn fn_starts_with(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('starts_with requires 2 arguments') }
	a := args[0]
	b := args[1]
	case_sensitive := if args.len > 2 { get_bool_arg(args[2], true) } else { true }
	match a {
		string {
			match b {
				string {
					if case_sensitive {
						return VrlValue(a.starts_with(b))
					}
					return VrlValue(a.to_lower().starts_with(b.to_lower()))
				}
				else { return error('starts_with second arg must be string') }
			}
		}
		else { return error('starts_with first arg must be string') }
	}
}

fn fn_ends_with(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('ends_with requires 2 arguments') }
	a := args[0]
	b := args[1]
	case_sensitive := if args.len > 2 { get_bool_arg(args[2], true) } else { true }
	match a {
		string {
			match b {
				string {
					if case_sensitive {
						return VrlValue(a.ends_with(b))
					}
					return VrlValue(a.to_lower().ends_with(b.to_lower()))
				}
				else { return error('ends_with second arg must be string') }
			}
		}
		else { return error('ends_with first arg must be string') }
	}
}

fn get_bool_arg(v VrlValue, default_val bool) bool {
	match v {
		bool { return v }
		else { return default_val }
	}
}

fn fn_length(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('length requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(i64(a.len)) }
		[]VrlValue { return VrlValue(i64(a.len)) }
		ObjectMap { return VrlValue(i64(a.len())) }
		else { return error('length requires string, array, or object') }
	}
}

fn fn_strip_whitespace(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('strip_whitespace requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.trim_space()) }
		else { return error('strip_whitespace requires a string') }
	}
}

fn fn_replace(args []VrlValue) !VrlValue {
	if args.len < 3 { return error('replace requires 3 arguments') }
	a0 := args[0]
	a1 := args[1]
	a2 := args[2]
	s := match a0 {
		string { a0 }
		else { return error('replace first arg must be string') }
	}
	replacement := match a2 {
		string { a2 }
		else { return error('replace third arg must be string') }
	}
	count := if args.len > 3 { get_int_arg(args[3], -1) } else { -1 }
	// Pattern can be a string or regex
	p := a1
	match p {
		string {
			if count == 1 {
				// Replace only first occurrence
				idx := s.index(p) or { return VrlValue(s) }
				result := s[..idx] + replacement + s[idx + p.len..]
				return VrlValue(result)
			}
			return VrlValue(s.replace(p, replacement))
		}
		VrlRegex {
			re := pcre.compile(normalize_regex_pattern(p.pattern)) or { return VrlValue(s) }
			if count == 1 {
				return VrlValue(re.replace(s, replacement))
			}
			return VrlValue(pcre_replace_all(re, s, replacement))
		}
		else { return error('replace second arg must be string or regex') }
	}
}

fn fn_split(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('split requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('split first arg must be string') }
	}
	limit := if args.len > 2 { get_int_arg(args[2], 0) } else { 0 }
	// Pattern can be string or regex
	p := a1
	match p {
		string {
			return split_string_with_limit(s, p, limit)
		}
		VrlRegex {
			return split_regex_with_limit(s, p.pattern, limit)
		}
		else { return error('split second arg must be string or regex') }
	}
}

fn split_string_with_limit(s string, delim string, limit int) !VrlValue {
	if limit <= 0 {
		parts := s.split(delim)
		mut result := []VrlValue{}
		for p in parts {
			result << VrlValue(p)
		}
		return VrlValue(result)
	}
	mut result := []VrlValue{}
	mut remaining := s
	for _ in 0 .. limit - 1 {
		idx := remaining.index(delim) or { break }
		result << VrlValue(remaining[..idx])
		remaining = remaining[idx + delim.len..]
	}
	result << VrlValue(remaining)
	return VrlValue(result)
}

fn split_regex_with_limit(s string, pattern string, limit int) !VrlValue {
	re := pcre.compile(normalize_regex_pattern(pattern)) or { return error('invalid regex in split') }
	mut result := []VrlValue{}
	mut pos := 0
	mut count := 0
	for pos <= s.len {
		if limit > 0 && count >= limit - 1 {
			result << VrlValue(s[pos..])
			return VrlValue(result)
		}
		m := re.find_from(s, pos) or {
			result << VrlValue(s[pos..])
			return VrlValue(result)
		}
		result << VrlValue(s[pos..m.start])
		pos = m.end
		count++
		if m.start == m.end {
			if pos < s.len {
				result << VrlValue(s[pos..pos + 1])
				count++
			}
			pos++
		}
	}
	return VrlValue(result)
}

// pcre_replace_all replaces all matches of a pcre regex in a string.
fn pcre_replace_all(re pcre.Regex, s string, replacement string) string {
	matches := re.find_all(s)
	if matches.len == 0 { return s }
	mut result := []u8{}
	mut pos := 0
	for m in matches {
		// Append text before this match
		for i in pos .. m.start {
			result << s[i]
		}
		// Append replacement
		for c in replacement {
			result << c
		}
		pos = m.end
	}
	// Append remaining text
	for i in pos .. s.len {
		result << s[i]
	}
	return result.bytestr()
}

fn fn_join(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('join requires at least 1 argument') }
	a0 := args[0]
	arr := match a0 {
		[]VrlValue { a0 }
		else { return error('join first arg must be array') }
	}
	sep := if args.len > 1 {
		s1 := args[1]
		match s1 {
			string { s1 }
			else { '' }
		}
	} else {
		''
	}
	mut parts := []string{}
	for item in arr {
		parts << vrl_to_string(item)
	}
	return VrlValue(parts.join(sep))
}

fn fn_slice(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('slice requires at least 2 arguments') }
	a1 := args[1]
	start := match a1 {
		i64 { a1 }
		else { return error('slice start must be integer') }
	}
	a0 := args[0]
	match a0 {
		string {
			s := a0 as string
			mut st := start
			if st < 0 { st = s.len + st }
			mut end := s.len
			if args.len > 2 { end = get_int_arg(args[2], s.len) }
			if st >= 0 && st <= s.len && end >= st && end <= s.len {
				result := s[st..end]
				return VrlValue(result)
			}
			return VrlValue(s)
		}
		[]VrlValue {
			arr := a0
			mut st := start
			if st < 0 { st = arr.len + st }
			mut end := arr.len
			if args.len > 2 { end = get_int_arg(args[2], arr.len) }
			if st >= 0 && st <= arr.len && end >= st && end <= arr.len {
				result := arr[st..end]
				return VrlValue(result)
			}
			return VrlValue(arr)
		}
		else { return error('slice requires string or array') }
	}
}

fn get_int_arg(v VrlValue, default_val int) int {
	match v {
		i64 {
			if v < 0 { return default_val + int(v) }
			return int(v)
		}
		else { return default_val }
	}
}

fn fn_strlen(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('strlen requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(i64(a.runes().len)) }
		else { return error('strlen requires a string') }
	}
}

fn fn_truncate(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('truncate requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('truncate first arg must be string') }
	}
	max_len := match a1 {
		i64 { a1 }
		f64 { i64(a1) }
		else { return error('truncate second arg must be integer') }
	}
	mut suffix := ''
	if args.len > 2 {
		a2 := args[2]
		match a2 {
			bool { if a2 { suffix = '...' } }
			string { suffix = a2 }
			else {}
		}
	}
	if s.len <= max_len { return VrlValue(s) }
	truncated := s[..max_len]
	return VrlValue(truncated + suffix)
}

// Type functions
fn fn_to_int(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_int requires 1 argument') }
	a := args[0]
	match a {
		i64 { return VrlValue(a) }
		f64 { return VrlValue(i64(a)) }
		bool {
			v := if a { i64(1) } else { i64(0) }
			return VrlValue(v)
		}
		string { return VrlValue(a.i64()) }
		VrlNull { return VrlValue(i64(0)) }
		Timestamp {
			return VrlValue(i64(a.t.unix()))
		}
		else { return error("can't convert to integer") }
	}
}

fn fn_to_float(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_float requires 1 argument') }
	a := args[0]
	match a {
		f64 { return VrlValue(a) }
		i64 { return VrlValue(f64(a)) }
		string { return VrlValue(a.f64()) }
		bool {
			v := if a { 1.0 } else { 0.0 }
			return VrlValue(v)
		}
		VrlNull { return VrlValue(0.0) }
		Timestamp {
			// Convert to Unix timestamp as float (seconds.microseconds)
			micros := a.t.unix_micro()
			return VrlValue(f64(micros) / 1_000_000.0)
		}
		else { return error("can't convert to float") }
	}
}

fn fn_to_bool(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_bool requires 1 argument') }
	a := args[0]
	match a {
		bool { return VrlValue(a) }
		string {
			lower := a.to_lower()
			if lower == 'true' || lower == 'yes' || lower == 'y' || lower == 't' || lower == '1' {
				return VrlValue(true)
			}
			if lower == 'false' || lower == 'no' || lower == 'n' || lower == 'f' || lower == '0' {
				return VrlValue(false)
			}
			return error("can't convert to boolean")
		}
		i64 { return VrlValue(a != 0) }
		f64 { return VrlValue(a != 0.0) }
		VrlNull { return VrlValue(false) }
		else { return error("can't convert to boolean") }
	}
}

fn fn_string(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('string requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a) }
		else { return error('expected string, got different type') }
	}
}

fn fn_is_type(args []VrlValue, type_name string) !VrlValue {
	if args.len < 1 { return VrlValue(false) }
	a := args[0]
	result := match type_name {
		'string' { a is string }
		'integer' { a is i64 }
		'float' { a is f64 }
		'boolean' { a is bool }
		'null' { a is VrlNull }
		'array' { a is []VrlValue }
		'object' { a is ObjectMap }
		else { false }
	}
	return VrlValue(result)
}

fn fn_is_nullish(args []VrlValue) !VrlValue {
	if args.len < 1 { return VrlValue(true) }
	a := args[0]
	match a {
		VrlNull { return VrlValue(true) }
		string {
			trimmed := a.trim_space()
			return VrlValue(trimmed.len == 0 || trimmed == '-')
		}
		else { return VrlValue(false) }
	}
}

// fn_type_def_static performs type inference on the argument.
// Uses static analysis for blocks and expressions, runtime eval + type tracking
// for variables and paths.
fn (mut rt Runtime) fn_type_def_static(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 {
		return error('type_def requires 1 argument')
	}
	arg := expr.args[0]
	result := rt.resolve_type_def(arg)
	return VrlValue(result)
}

// resolve_type_def determines the type for a type_def() argument.
// Uses a hybrid approach: runtime value for variables/paths, unioned with
// tracked type info (which includes union types from conditional branches).
// For complex expressions (blocks, etc.), uses static inference.
fn (mut rt Runtime) resolve_type_def(arg Expr) ObjectMap {
	match arg {
		IdentExpr {
			// Get runtime value type
			val := rt.eval(arg) or { VrlValue(VrlNull{}) }
			runtime_type := type_from_value(val)
			// Union with tracked type (includes conditional branch info)
			if tracked := rt.type_vars[arg.name] {
				return type_union(runtime_type, tracked)
			}
			return runtime_type
		}
		PathExpr {
			// Get runtime value type
			val := rt.eval(arg) or { VrlValue(VrlNull{}) }
			runtime_type := type_from_value(val)
			// Union with tracked type
			key := if arg.path == '.' {
				'.'
			} else if arg.path.starts_with('.') {
				arg.path[1..]
			} else {
				arg.path
			}
			mut result_type := runtime_type
			if tracked := rt.type_paths[key] {
				result_type = type_union(result_type, tracked)
			} else if arg.path != '.' {
				// External path never assigned in this program — type is "any"
				// because the event could contain any type for this field
				mut any_type := new_object_map()
				any_type.set('any', VrlValue(true))
				return any_type
			}
			// For root object '.', also overlay individual path types
			if arg.path == '.' {
				result_type = rt.overlay_path_types(result_type)
			}
			return result_type
		}
		MetaPathExpr {
			// Get runtime metadata value and derive type from it
			val := rt.get_meta(arg.path) or { VrlValue(VrlNull{}) }
			return type_from_value(val)
		}
		IndexExpr {
			// For indexing (x[1]), use static inference
			result := rt.infer_type(arg)
			// If static inference returned any_type, try runtime eval
			if result.len() == 1 && (result.get('any') or { return result }) == VrlValue(true) {
				val := rt.eval(arg) or { return result }
				return type_from_value(val)
			}
			return result
		}
		BlockExpr {
			// Evaluate the block at runtime and use the actual result type
			val := rt.eval(arg) or { return rt.infer_type(arg) }
			runtime_type := type_from_value(val)
			// Union with static inference to capture error/alternative paths
			static_type := rt.infer_type(arg)
			if static_type.len() > 0 {
				return type_union(runtime_type, static_type)
			}
			return runtime_type
		}
		else {
			// For function calls, etc. use static inference
			return rt.infer_type(arg)
		}
	}
}

// Object/path functions
fn (mut rt Runtime) fn_del(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('del requires 1 argument') }
	path_expr := expr.args[0]
	match path_expr {
		PathExpr {
			if path_expr.path == '.' {
				mut old := VrlValue(VrlNull{})
				if rt.has_root_scalar {
					old = rt.root_scalar
				} else if rt.has_root_array {
					old = VrlValue(rt.root_array.clone())
				} else {
					old = VrlValue(rt.object.clone_map())
				}
				// After del(.), root is null
				rt.object.clear()
				rt.has_root_array = false
				rt.root_scalar = VrlValue(VrlNull{})
				rt.has_root_scalar = true
				// Update type tracking: after del(.), type is null
				mut null_type := new_object_map()
				null_type.set('null', VrlValue(true))
				rt.type_paths['.'] = null_type
				return old
			}
			clean := if path_expr.path.starts_with('.') { path_expr.path[1..] } else { path_expr.path }
			parts := split_path_segments(clean)
			if parts.len == 1 {
				val := rt.object.delete(parts[0])
				return val
			}
			return rt.del_nested_path(parts)
		}
		MetaPathExpr {
			if path_expr.path == '%' {
				old := VrlValue(rt.metadata.clone_map())
				rt.metadata.clear()
				return old
			}
			clean := if path_expr.path.starts_with('%') { path_expr.path[1..] } else { path_expr.path }
			val := rt.metadata.delete(clean)
			return val
		}
		IndexExpr {
			return rt.del_index_expr(path_expr)
		}
		else {
			return rt.eval(path_expr)
		}
	}
}

fn (mut rt Runtime) del_nested_path(parts []string) !VrlValue {
	if parts.len == 2 {
		if top_val := rt.object.get(parts[0]) {
			tv := top_val
			match tv {
				ObjectMap {
					val := tv.get(parts[1]) or { VrlValue(VrlNull{}) }
					mut m := tv.clone_map()
					m.delete(parts[1])
					rt.object.set(parts[0], VrlValue(m))
					return val
				}
				else {}
			}
		}
	}
	if parts.len > 2 {
		mut current := rt.object.get(parts[0]) or { return VrlValue(VrlNull{}) }
		for i in 1 .. parts.len - 1 {
			c := current
			match c {
				ObjectMap {
					current = c.get(parts[i]) or { return VrlValue(VrlNull{}) }
				}
				else { return VrlValue(VrlNull{}) }
			}
		}
		c := current
		match c {
			ObjectMap {
				last_key := parts[parts.len - 1]
				val := c.get(last_key) or { VrlValue(VrlNull{}) }
				mut m := c.clone_map()
				m.delete(last_key)
				rt.set_nested_path(parts[..parts.len - 1], VrlValue(m))
				return val
			}
			else { return VrlValue(VrlNull{}) }
		}
	}
	return VrlValue(VrlNull{})
}

fn (mut rt Runtime) del_index_expr(idx_expr IndexExpr) !VrlValue {
	container_expr := idx_expr.expr[0]
	index_expr_v := idx_expr.index[0]
	key_val := rt.eval(index_expr_v)!
	kv := key_val
	key := match kv {
		string { kv }
		else { return VrlValue(VrlNull{}) }
	}

	if container_expr is IdentExpr {
		name := container_expr.name
		if existing := rt.vars.get(name) {
			e := existing
			match e {
				ObjectMap {
					val := e.get(key) or { VrlValue(VrlNull{}) }
					mut m := e.clone_map()
					m.delete(key)
					rt.vars.set(name, VrlValue(m))
					return val
				}
				else {}
			}
		}
	} else if container_expr is PathExpr {
		if existing := rt.get_path(container_expr.path) {
			e := existing
			match e {
				ObjectMap {
					val := e.get(key) or { VrlValue(VrlNull{}) }
					mut m := e.clone_map()
					m.delete(key)
					rt.assign_to(Expr(container_expr), VrlValue(m))
					return val
				}
				else {}
			}
		}
	} else if container_expr is IndexExpr {
		parent_val := rt.eval(Expr(container_expr))!
		pv := parent_val
		match pv {
			ObjectMap {
				val := pv.get(key) or { VrlValue(VrlNull{}) }
				mut m := pv.clone_map()
				m.delete(key)
				rt.assign_index(container_expr, VrlValue(m))
				return val
			}
			else {}
		}
	}
	return VrlValue(VrlNull{})
}

fn (mut rt Runtime) fn_exists(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('exists requires 1 argument') }
	path_expr := expr.args[0]
	match path_expr {
		PathExpr {
			if path_expr.path == '.' { return VrlValue(true) }
			clean := if path_expr.path.starts_with('.') { path_expr.path[1..] } else { path_expr.path }
			return VrlValue(rt.object.has(clean))
		}
		else { return VrlValue(false) }
	}
}

fn fn_keys(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('keys requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			all_keys := a.keys()
			mut result := []VrlValue{cap: all_keys.len}
			for k in all_keys {
				result << VrlValue(k)
			}
			return VrlValue(result)
		}
		else { return error('keys requires an object') }
	}
}

fn fn_values(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('values requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			if a.is_large {
				mut result := []VrlValue{}
				for _, v in a.hm {
					result << v
				}
				return VrlValue(result)
			}
			return VrlValue(a.vs.clone())
		}
		else { return error('values requires an object') }
	}
}

fn fn_flatten(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('flatten requires 1 argument') }
	sep := if args.len > 1 {
		s := args[1]
		match s { string { s } else { '.' } }
	} else { '.' }
	a := args[0]
	match a {
		ObjectMap {
			mut result := new_object_map()
			flatten_object(a, '', sep, mut result)
			return VrlValue(result)
		}
		[]VrlValue {
			mut result := []VrlValue{}
			flatten_array(a, mut result)
			return VrlValue(result)
		}
		else { return error('flatten requires object or array') }
	}
}

fn flatten_object(obj ObjectMap, prefix string, sep string, mut result ObjectMap) {
	if obj.is_large {
		for k, v in obj.hm {
			full_key := if prefix.len > 0 { '${prefix}${sep}${k}' } else { k }
			val := v
			match val {
				ObjectMap {
					flatten_object(val, full_key, sep, mut result)
				}
				else {
					result.set(full_key, v)
				}
			}
		}
	} else {
		for i in 0 .. obj.ks.len {
			full_key := if prefix.len > 0 { '${prefix}${sep}${obj.ks[i]}' } else { obj.ks[i] }
			val := obj.vs[i]
			match val {
				ObjectMap {
					flatten_object(val, full_key, sep, mut result)
				}
				else {
					result.set(full_key, obj.vs[i])
				}
			}
		}
	}
}

fn flatten_array(arr []VrlValue, mut result []VrlValue) {
	for item in arr {
		i := item
		match i {
			[]VrlValue {
				flatten_array(i, mut result)
			}
			else {
				result << item
			}
		}
	}
}

fn fn_unflatten(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('unflatten requires 1 argument') }
	sep := if args.len > 1 {
		a1 := args[1]
		match a1 {
			string { a1 }
			else { '.' }
		}
	} else {
		'.'
	}
	a := args[0]
	match a {
		ObjectMap {
			mut result := new_object_map()
			all_keys := a.keys()
			for k in all_keys {
				v := a.get(k) or { VrlValue(VrlNull{}) }
				unflatten_set_nested(mut result, k, v, sep)
			}
			return VrlValue(result)
		}
		else { return error('unflatten requires an object') }
	}
}

// unflatten_set_nested sets a value in a nested object map using a dotted key path.
fn unflatten_set_nested(mut obj ObjectMap, key string, val VrlValue, sep string) {
	parts := key.split(sep)
	if parts.len <= 1 {
		obj.set(key, val)
		return
	}
	// Handle first part, recursively nest into it
	first := parts[0]
	remaining := parts[1..].join(sep)
	if obj.has(first) {
		existing := obj.get(first) or { VrlValue(new_object_map()) }
		e := existing
		match e {
			ObjectMap {
				mut m := e.clone_map()
				unflatten_set_nested(mut m, remaining, val, sep)
				obj.set(first, VrlValue(m))
			}
			else {
				mut m := new_object_map()
				unflatten_set_nested(mut m, remaining, val, sep)
				obj.set(first, VrlValue(m))
			}
		}
	} else {
		mut m := new_object_map()
		unflatten_set_nested(mut m, remaining, val, sep)
		obj.set(first, VrlValue(m))
	}
}

fn fn_merge(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('merge requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	match a0 {
		ObjectMap {
			match a1 {
				ObjectMap {
					mut result := a0.clone_map()
					if a1.is_large {
						for k, v in a1.hm {
							result.set(k, v)
						}
					} else {
						for i in 0 .. a1.ks.len {
							result.set(a1.ks[i], a1.vs[i])
						}
					}
					return VrlValue(result)
				}
				else { return error('only objects can be merged') }
			}
		}
		else { return error('only objects can be merged') }
	}
}

fn fn_compact(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('compact requires 1 argument') }
	// Parse optional flags: null, string, object, array, nullish, recursive
	// Defaults: null=true, string=true, object=true, array=true, nullish=false, recursive=true
	null_flag := if args.len > 1 { get_bool_arg(args[1], true) } else { true }
	string_flag := if args.len > 2 { get_bool_arg(args[2], true) } else { true }
	object_flag := if args.len > 3 { get_bool_arg(args[3], true) } else { true }
	array_flag := if args.len > 4 { get_bool_arg(args[4], true) } else { true }
	nullish_flag := if args.len > 5 { get_bool_arg(args[5], false) } else { false }
	recursive := if args.len > 6 { get_bool_arg(args[6], true) } else { true }
	return compact_value(args[0], null_flag, string_flag, object_flag, array_flag, nullish_flag, recursive)
}

fn compact_value(v VrlValue, null_flag bool, string_flag bool, object_flag bool, array_flag bool, nullish_flag bool, recursive bool) !VrlValue {
	a := v
	match a {
		[]VrlValue {
			mut result := []VrlValue{}
			for item in a {
				mut val := item
				if recursive {
					val = compact_value(item, null_flag, string_flag, object_flag, array_flag, nullish_flag, recursive) or { item }
				}
				if should_compact(val, null_flag, string_flag, object_flag, array_flag, nullish_flag) {
					continue
				}
				result << val
			}
			return VrlValue(result)
		}
		ObjectMap {
			mut result := new_object_map()
			all_keys := a.keys()
			for k in all_keys {
				item := a.get(k) or { VrlValue(VrlNull{}) }
				mut val := item
				if recursive {
					val = compact_value(item, null_flag, string_flag, object_flag, array_flag, nullish_flag, recursive) or { item }
				}
				if should_compact(val, null_flag, string_flag, object_flag, array_flag, nullish_flag) {
					continue
				}
				result.set(k, val)
			}
			return VrlValue(result)
		}
		else { return v }
	}
}

fn should_compact(v VrlValue, null_flag bool, string_flag bool, object_flag bool, array_flag bool, nullish_flag bool) bool {
	a := v
	match a {
		VrlNull { return null_flag || nullish_flag }
		string {
			if nullish_flag {
				trimmed := a.trim_space()
				return trimmed.len == 0 || trimmed == '-'
			}
			return string_flag && a.len == 0
		}
		[]VrlValue { return array_flag && a.len == 0 }
		ObjectMap { return object_flag && a.len() == 0 }
		else { return false }
	}
}

fn fn_push(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('push requires 2 arguments') }
	a := args[0]
	match a {
		[]VrlValue {
			mut result := a.clone()
			result << args[1]
			return VrlValue(result)
		}
		else { return error('push first arg must be array') }
	}
}

fn fn_append(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('append requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	match a0 {
		[]VrlValue {
			match a1 {
				[]VrlValue {
					mut result := a0.clone()
					for item in a1 {
						result << item
					}
					return VrlValue(result)
				}
				else { return error('append second arg must be array') }
			}
		}
		else { return error('append first arg must be array') }
	}
}

fn fn_first_arg(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('requires 1 argument') }
	return args[0]
}

// save_closure_params saves the current values of closure parameter variables and returns them.
fn (rt Runtime) save_closure_params(params []string) map[string]VrlValue {
	mut saved := map[string]VrlValue{}
	for p in params {
		name := p.trim_left('_')
		if v := rt.vars.get(name) {
			saved[name] = v
		}
	}
	return saved
}

// restore_closure_params restores saved closure parameter variables.
fn (mut rt Runtime) restore_closure_params(saved map[string]VrlValue, params []string) {
	for p in params {
		name := p.trim_left('_')
		if v := saved[name] {
			rt.vars.set(name, v)
		} else {
			rt.vars.delete(name)
		}
	}
}

fn (mut rt Runtime) fn_filter(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('filter requires 1 argument') }
	container := rt.eval(expr.args[0])!
	if expr.closure.len == 0 { return container }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		saved := rt.save_closure_params(closure_expr.params)
		c := container
		match c {
			[]VrlValue {
				mut result := []VrlValue{}
				for i, item in c {
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(i64(i)))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1].trim_left('_'), item)
					}
					cond := rt.eval(closure_expr.body[0])!
					if rt.returned { rt.returned = false }
					if is_truthy(cond) { result << item }
				}
				rt.restore_closure_params(saved, closure_expr.params)
				return VrlValue(result)
			}
			ObjectMap {
				mut result := new_object_map()
				mut all_keys := c.keys()
				all_keys.sort()
				for k in all_keys {
					val := c.get(k) or { VrlValue(VrlNull{}) }
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(k))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1].trim_left('_'), val)
					}
					cond := rt.eval(closure_expr.body[0])!
					if rt.returned { rt.returned = false }
					if is_truthy(cond) { result.set(k, val) }
				}
				rt.restore_closure_params(saved, closure_expr.params)
				return VrlValue(result)
			}
			else { return container }
		}
	}
	return container
}

fn (mut rt Runtime) fn_for_each(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('for_each requires 1 argument') }
	container := rt.eval(expr.args[0])!
	if expr.closure.len == 0 { return VrlValue(VrlNull{}) }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		saved := rt.save_closure_params(closure_expr.params)
		c := container
		match c {
			[]VrlValue {
				for i, item in c {
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(i64(i)))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1].trim_left('_'), item)
					}
					rt.eval(closure_expr.body[0])!
					if rt.returned {
						rt.returned = false
						break
					}
				}
			}
			ObjectMap {
				mut all_keys := c.keys()
				all_keys.sort()
				for k in all_keys {
					val := c.get(k) or { VrlValue(VrlNull{}) }
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(k))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1].trim_left('_'), val)
					}
					rt.eval(closure_expr.body[0])!
					if rt.returned {
						rt.returned = false
						break
					}
				}
			}
			else {}
		}
		rt.restore_closure_params(saved, closure_expr.params)
	}
	return VrlValue(VrlNull{})
}

fn (mut rt Runtime) fn_map_keys(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('map_keys requires 1 argument') }
	// Check for recursive named arg
	has_named := expr.arg_names.len > 0 && expr.arg_names.any(it.len > 0)
	mut recursive := false
	if has_named {
		for i, an in expr.arg_names {
			if an == 'recursive' {
				rv := rt.eval(expr.args[i])!
				r := rv
				match r {
					bool { recursive = r }
					else {}
				}
			}
		}
	}
	// Find the positional argument (first non-named arg)
	mut container_idx := 0
	for i, an in expr.arg_names {
		if an.len == 0 {
			container_idx = i
			break
		}
	}
	container := rt.eval(expr.args[container_idx])!
	if expr.closure.len == 0 { return container }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		return rt.map_keys_impl(container, closure_expr, recursive)
	}
	return container
}

fn (mut rt Runtime) map_keys_impl(container VrlValue, closure_expr ClosureExpr, recursive bool) !VrlValue {
	c := container
	match c {
		ObjectMap {
			saved := rt.save_closure_params(closure_expr.params)
			mut result := new_object_map()
			mut all_keys := c.keys()
				all_keys.sort()
			for k in all_keys {
				val := c.get(k) or { VrlValue(VrlNull{}) }
				if closure_expr.params.len > 0 {
					rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(k))
				}
				new_key := rt.eval(closure_expr.body[0])!
				nk := new_key
				final_key := match nk {
					string { nk }
					else { k }
				}
				if recursive {
					result.set(final_key, rt.map_keys_impl(val, closure_expr, true)!)
				} else {
					result.set(final_key, val)
				}
			}
			rt.restore_closure_params(saved, closure_expr.params)
			return VrlValue(result)
		}
		[]VrlValue {
			if recursive {
				mut result := []VrlValue{}
				for item in c {
					result << rt.map_keys_impl(item, closure_expr, true)!
				}
				return VrlValue(result)
			}
			return container
		}
		else { return container }
	}
}

fn (mut rt Runtime) fn_map_values(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('map_values requires 1 argument') }
	// Check for recursive named arg
	has_named := expr.arg_names.len > 0 && expr.arg_names.any(it.len > 0)
	mut recursive := false
	if has_named {
		for i, an in expr.arg_names {
			if an == 'recursive' {
				rv := rt.eval(expr.args[i])!
				r := rv
				match r {
					bool { recursive = r }
					else {}
				}
			}
		}
	}
	mut container_idx := 0
	for i, an in expr.arg_names {
		if an.len == 0 {
			container_idx = i
			break
		}
	}
	container := rt.eval(expr.args[container_idx])!
	if expr.closure.len == 0 { return container }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		return rt.map_values_impl(container, closure_expr, recursive)
	}
	return container
}

fn (mut rt Runtime) map_values_impl(container VrlValue, closure_expr ClosureExpr, recursive bool) !VrlValue {
	c := container
	match c {
		ObjectMap {
			saved := rt.save_closure_params(closure_expr.params)
			mut result := new_object_map()
			mut all_keys := c.keys()
				all_keys.sort()
			for k in all_keys {
				val := c.get(k) or { VrlValue(VrlNull{}) }
				if recursive {
					// For recursive, only apply closure to leaf values
					v := val
					match v {
						ObjectMap {
							result.set(k, rt.map_values_impl(val, closure_expr, true)!)
							continue
						}
						[]VrlValue {
							result.set(k, rt.map_values_impl(val, closure_expr, true)!)
							continue
						}
						else {}
					}
				}
				if closure_expr.params.len > 0 {
					rt.vars.set(closure_expr.params[0].trim_left('_'), val)
				}
				new_val := rt.eval(closure_expr.body[0])!
				result.set(k, new_val)
			}
			rt.restore_closure_params(saved, closure_expr.params)
			return VrlValue(result)
		}
		[]VrlValue {
			if recursive {
				mut result := []VrlValue{}
				for item in c {
					result << rt.map_values_impl(item, closure_expr, recursive)!
				}
				return VrlValue(result)
			}
			// Apply closure to each element
			saved := rt.save_closure_params(closure_expr.params)
			mut result := []VrlValue{}
			for item in c {
				if closure_expr.params.len > 0 {
					rt.vars.set(closure_expr.params[0].trim_left('_'), item)
				}
				new_val := rt.eval(closure_expr.body[0])!
				result << new_val
			}
			rt.restore_closure_params(saved, closure_expr.params)
			return VrlValue(result)
		}
		else { return container }
	}
}

fn fn_encode_json(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('encode_json requires 1 argument') }
	pretty := if args.len > 1 { get_bool_arg(args[1], false) } else { false }
	if pretty {
		return VrlValue(vrl_to_json_pretty(args[0], 0))
	}
	return VrlValue(vrl_to_json(args[0]))
}

fn fn_decode_json(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('parse_json requires 1 argument') }
	a := args[0]
	max_depth := if args.len > 1 { get_int_arg(args[1], 0) } else { 0 }
	match a {
		string {
			if max_depth > 0 {
				return parse_json_with_depth(a, max_depth, 0)
			}
			return parse_json_recursive(a)
		}
		else { return error('parse_json requires a string argument') }
	}
}

fn parse_json_with_depth(s string, max_depth int, current_depth int) !VrlValue {
	trimmed := s.trim_space()
	if trimmed.len == 0 { return VrlValue(VrlNull{}) }
	if trimmed == 'null' { return VrlValue(VrlNull{}) }
	if trimmed == 'true' { return VrlValue(true) }
	if trimmed == 'false' { return VrlValue(false) }
	if trimmed.starts_with('"') && trimmed.ends_with('"') {
		end := trimmed.len - 1
		return VrlValue(trimmed[1..end])
	}
	if trimmed[0].is_digit() || (trimmed[0] == `-` && trimmed.len > 1) {
		if trimmed.contains('.') { return VrlValue(trimmed.f64()) }
		return VrlValue(trimmed.i64())
	}
	if current_depth >= max_depth {
		// At max depth, return the raw JSON string
		return VrlValue(trimmed)
	}
	if trimmed.starts_with('[') {
		end := trimmed.len - 1
		inner := trimmed[1..end].trim_space()
		if inner.len == 0 { return VrlValue([]VrlValue{}) }
		parts := split_json_top_level(inner)
		mut result := []VrlValue{}
		for part in parts {
			result << parse_json_with_depth(part.trim_space(), max_depth, current_depth + 1)!
		}
		return VrlValue(result)
	}
	if trimmed.starts_with('{') {
		end := trimmed.len - 1
		inner := trimmed[1..end].trim_space()
		if inner.len == 0 { return VrlValue(new_object_map()) }
		parts := split_json_top_level(inner)
		mut result := new_object_map()
		for part in parts {
			colon_idx := find_colon(part)
			if colon_idx > 0 {
				key_str := part[..colon_idx].trim_space()
				val_str := part[colon_idx + 1..].trim_space()
				mut key := key_str
				if key_str.starts_with('"') && key_str.ends_with('"') {
					kend := key_str.len - 1
					key = key_str[1..kend]
				}
				result.set(key, parse_json_with_depth(val_str, max_depth, current_depth + 1)!)
			}
		}
		return VrlValue(result)
	}
	return error('unable to parse JSON: ${trimmed}')
}

// Simple recursive JSON parser that produces VrlValues directly
fn parse_json_recursive(s string) !VrlValue {
	trimmed := s.trim_space()
	if trimmed.len == 0 { return VrlValue(VrlNull{}) }
	if trimmed == 'null' { return VrlValue(VrlNull{}) }
	if trimmed == 'true' { return VrlValue(true) }
	if trimmed == 'false' { return VrlValue(false) }
	if trimmed.starts_with('"') && trimmed.ends_with('"') {
		end := trimmed.len - 1
		inner := trimmed[1..end]
		return VrlValue(unescape_json_string(inner))
	}
	if trimmed[0].is_digit() || (trimmed[0] == `-` && trimmed.len > 1) {
		if trimmed.contains('.') {
			fv := trimmed.f64()
			return VrlValue(fv)
		}
		iv := trimmed.i64()
		return VrlValue(iv)
	}
	if trimmed.starts_with('[') {
		return parse_json_array(trimmed)
	}
	if trimmed.starts_with('{') {
		return parse_json_object(trimmed)
	}
	return error('unable to parse JSON: ${trimmed}')
}

fn parse_json_array(s string) !VrlValue {
	if s.len < 2 { return error('invalid JSON array') }
	end := s.len - 1
	inner := s[1..end].trim_space()
	if inner.len == 0 { return VrlValue([]VrlValue{}) }
	parts := split_json_top_level(inner)
	mut result := []VrlValue{}
	for part in parts {
		val := parse_json_recursive(part.trim_space())!
		result << val
	}
	return VrlValue(result)
}

fn parse_json_object(s string) !VrlValue {
	if s.len < 2 { return error('invalid JSON object') }
	end := s.len - 1
	inner := s[1..end].trim_space()
	if inner.len == 0 { return VrlValue(new_object_map()) }
	parts := split_json_top_level(inner)
	mut result := new_object_map()
	for part in parts {
		colon_idx := find_colon(part)
		if colon_idx > 0 {
			key_str := part[..colon_idx].trim_space()
			val_str := part[colon_idx + 1..].trim_space()
			mut key := key_str
			if key_str.starts_with('"') && key_str.ends_with('"') {
				kend := key_str.len - 1
				key = key_str[1..kend]
			}
			val := parse_json_recursive(val_str)!
			result.set(key, val)
		}
	}
	return VrlValue(result)
}

fn find_colon(s string) int {
	mut depth := 0
	mut in_string := false
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `"` && (i == 0 || s[i - 1] != `\\`) { in_string = !in_string }
		if !in_string {
			if ch == `[` || ch == `{` { depth++ }
			if ch == `]` || ch == `}` { depth-- }
			if ch == `:` && depth == 0 { return i }
		}
	}
	return -1
}

fn split_json_top_level(s string) []string {
	mut parts := []string{}
	mut depth := 0
	mut in_string := false
	mut start := 0
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `"` && (i == 0 || s[i - 1] != `\\`) { in_string = !in_string }
		if !in_string {
			if ch == `[` || ch == `{` { depth++ }
			if ch == `]` || ch == `}` { depth-- }
			if ch == `,` && depth == 0 {
				parts << s[start..i]
				start = i + 1
			}
		}
	}
	if start < s.len {
		parts << s[start..]
	}
	return parts
}

// unescape_json_string processes JSON escape sequences in a string.
fn unescape_json_string(s string) string {
	if !s.contains('\\') {
		return s
	}
	mut result := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `\\` && i + 1 < s.len {
			i++
			match s[i] {
				`"` { result << `"` }
				`\\` { result << `\\` }
				`/` { result << `/` }
				`n` { result << `\n` }
				`t` { result << `\t` }
				`r` { result << `\r` }
				`b` { result << 0x08 }
				`f` { result << 0x0c }
				`u` {
					// Unicode escape \uXXXX
					if i + 4 < s.len {
						hex := s[i + 1..i + 5]
						code := u32(0)
						mut valid := true
						mut cp := u32(0)
						for h in hex.bytes() {
							cp <<= 4
							if h >= `0` && h <= `9` {
								cp |= u32(h - `0`)
							} else if h >= `a` && h <= `f` {
								cp |= u32(h - `a` + 10)
							} else if h >= `A` && h <= `F` {
								cp |= u32(h - `A` + 10)
							} else {
								valid = false
								break
							}
						}
						_ = code
						if valid {
							// Encode as UTF-8
							if cp < 0x80 {
								result << u8(cp)
							} else if cp < 0x800 {
								result << u8(0xC0 | (cp >> 6))
								result << u8(0x80 | (cp & 0x3F))
							} else {
								result << u8(0xE0 | (cp >> 12))
								result << u8(0x80 | ((cp >> 6) & 0x3F))
								result << u8(0x80 | (cp & 0x3F))
							}
							i += 4
						} else {
							result << `\\`
							result << `u`
						}
					} else {
						result << `\\`
						result << `u`
					}
				}
				else {
					result << `\\`
					result << s[i]
				}
			}
		} else {
			result << s[i]
		}
		i++
	}
	return result.bytestr()
}

// Math functions
fn fn_abs(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('abs requires 1 argument') }
	a := args[0]
	match a {
		i64 {
			v := if a < 0 { -a } else { a }
			return VrlValue(v)
		}
		f64 {
			v := if a < 0.0 { -a } else { a }
			return VrlValue(v)
		}
		else { return error('abs requires a number') }
	}
}

fn fn_ceil(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('ceil requires 1 argument') }
	precision := if args.len > 1 {
		p := args[1]
		match p { i64 { p } else { i64(0) } }
	} else { i64(0) }
	a := args[0]
	match a {
		f64 {
			if precision > 0 {
				mut mult := 1.0
				for _ in 0 .. precision { mult *= 10.0 }
				return VrlValue(math.ceil(a * mult) / mult)
			}
			return VrlValue(i64(math.ceil(a)))
		}
		i64 {
			if precision > 0 { return VrlValue(f64(a)) }
			return VrlValue(a)
		}
		else { return error('ceil requires a number') }
	}
}

fn fn_floor(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('floor requires 1 argument') }
	precision := if args.len > 1 {
		p := args[1]
		match p { i64 { p } else { i64(0) } }
	} else { i64(0) }
	a := args[0]
	match a {
		f64 {
			if precision > 0 {
				mut mult := 1.0
				for _ in 0 .. precision { mult *= 10.0 }
				return VrlValue(math.floor(a * mult) / mult)
			}
			return VrlValue(i64(math.floor(a)))
		}
		i64 {
			if precision > 0 { return VrlValue(f64(a)) }
			return VrlValue(a)
		}
		else { return error('floor requires a number') }
	}
}

fn fn_round(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('round requires 1 argument') }
	precision := if args.len > 1 {
		p := args[1]
		match p {
			i64 { p }
			else { 0 }
		}
	} else { 0 }
	a := args[0]
	match a {
		f64 {
			if precision == 0 {
				return VrlValue(i64(a + 0.5))
			}
			mut mult := 1.0
			for _ in 0 .. precision { mult *= 10.0 }
			return VrlValue(f64(i64(a * mult + 0.5)) / mult)
		}
		i64 { return VrlValue(a) }
		else { return error('round requires a number') }
	}
}

fn fn_mod(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('mod requires 2 arguments') }
	return arith_mod(args[0], args[1])
}

fn fn_assert(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('assert requires 1 argument') }
	if !is_truthy(args[0]) {
		msg := if args.len > 1 { vrl_to_string(args[1]) } else { 'assertion failed' }
		return error(msg)
	}
	return VrlValue(true)
}

fn fn_assert_eq(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('assert_eq requires 2 arguments') }
	if !values_equal(args[0], args[1]) {
		msg := if args.len > 2 {
			vrl_to_string(args[2])
		} else {
			'assertion failed: ${vrl_to_json(args[0])} != ${vrl_to_json(args[1])}'
		}
		return error(msg)
	}
	return VrlValue(true)
}

fn fn_ensure_array(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('array requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue { return VrlValue(a) }
		else { return error('expected array, got ${vrl_type_name(a)}') }
	}
}

fn fn_ensure_object(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('object requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap { return VrlValue(a) }
		else { return error('expected object, got ${vrl_type_name(a)}') }
	}
}

fn fn_pop(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('pop requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue {
			if a.len == 0 { return VrlValue([]VrlValue{}) }
			return VrlValue(a[..a.len - 1])
		}
		else { return error('pop requires an array') }
	}
}

fn fn_match(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('match requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('match first arg must be string') }
	}
	pattern := match a1 {
		VrlRegex { a1.pattern }
		string { a1 }
		else { return error('match second arg must be regex') }
	}
	// Use pcre for matching (supports (?i) and other flags)
	re := pcre.compile(normalize_regex_pattern(pattern)) or { return error('invalid regex: ${pattern}') }
	if _ := re.find(s) {
		return VrlValue(true)
	}
	return VrlValue(false)
}

fn fn_match_any(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('match_any requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('match_any first arg must be string') }
	}
	patterns := match a1 {
		[]VrlValue { a1 }
		else { return error('match_any second arg must be array') }
	}
	for p in patterns {
		pat := match p {
			VrlRegex { p.pattern }
			string { p }
			else { continue }
		}
		re := pcre.compile(normalize_regex_pattern(pat)) or { continue }
		if _ := re.find(s) {
			return VrlValue(true)
		}
	}
	return VrlValue(false)
}

fn fn_includes(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('includes requires 2 arguments') }
	a := args[0]
	match a {
		[]VrlValue {
			for item in a {
				if values_equal(item, args[1]) { return VrlValue(true) }
			}
			return VrlValue(false)
		}
		else { return error('includes first arg must be array') }
	}
}

fn fn_contains_all(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('contains_all requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	cs := if args.len > 2 { get_bool_arg(args[2], true) } else { true }
	s := match a0 {
		string { if cs { a0 } else { a0.to_lower() } }
		else { return error('contains_all first arg must be string') }
	}
	needles := match a1 {
		[]VrlValue { a1 }
		else { return error('contains_all second arg must be array') }
	}
	for needle in needles {
		n := match needle {
			string { if cs { needle } else { needle.to_lower() } }
			else { continue }
		}
		if !s.contains(n) { return VrlValue(false) }
	}
	return VrlValue(true)
}

fn fn_find(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('find requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('find first arg must be string') }
	}
	from := if args.len > 2 {
		a2 := args[2]
		match a2 {
			i64 { a2 }
			else { 0 }
		}
	} else {
		0
	}
	search_str := if from > 0 && from < s.len { s[from..] } else { s }
	a1v := a1
	match a1v {
		VrlRegex {
			re := pcre.compile(normalize_regex_pattern(a1v.pattern)) or { return VrlValue(VrlNull{}) }
			if m := re.find(search_str) {
				return VrlValue(i64(m.start) + from)
			}
			return VrlValue(VrlNull{})
		}
		string {
			idx := search_str.index(a1v) or { return VrlValue(VrlNull{}) }
			return VrlValue(i64(idx) + from)
		}
		else { return error('find second arg must be string or regex') }
	}
}

fn fn_get(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('get requires 2 arguments') }
	container := args[0]
	path := args[1]
	// Convert path to array of segments
	segments := get_path_segments(path)
	return get_nested(container, segments)
}

fn get_path_segments(path VrlValue) []VrlValue {
	p := path
	match p {
		[]VrlValue { return p }
		string {
			parts := p.split('.')
			mut result := []VrlValue{}
			for part in parts {
				result << VrlValue(part)
			}
			return result
		}
		else { return [path] }
	}
}

fn get_nested(container VrlValue, segments []VrlValue) !VrlValue {
	if segments.len == 0 { return container }
	c := container
	seg := segments[0]
	rest := segments[1..]
	match c {
		ObjectMap {
			s := seg
			key := match s {
				string { s }
				i64 { '${s}' }
				else { return VrlValue(VrlNull{}) }
			}
			val := c.get(key) or { return VrlValue(VrlNull{}) }
			return get_nested(val, rest)
		}
		[]VrlValue {
			s := seg
			idx := match s {
				i64 { if s < 0 { c.len + s } else { s } }
				string {
					// Only numeric strings are valid array indices
					if s.len > 0 && (s[0].is_digit() || (s[0] == `-` && s.len > 1)) {
						s.int()
					} else {
						return VrlValue(VrlNull{})
					}
				}
				else { return VrlValue(VrlNull{}) }
			}
			if idx >= 0 && idx < c.len {
				return get_nested(c[idx], rest)
			}
			return VrlValue(VrlNull{})
		}
		else { return VrlValue(VrlNull{}) }
	}
}

fn fn_set(args []VrlValue) !VrlValue {
	if args.len < 3 { return error('set requires 3 arguments') }
	container := args[0]
	path := args[1]
	value := args[2]
	segments := get_path_segments(path)
	return set_nested(container, segments, value)
}

fn set_nested(container VrlValue, segments []VrlValue, value VrlValue) !VrlValue {
	if segments.len == 0 { return value }
	c := container
	seg := segments[0]
	rest := segments[1..]
	match c {
		ObjectMap {
			s := seg
			key := match s {
				string { s }
				i64 { '${s}' }
				else { return container }
			}
			existing := c.get(key) or { VrlValue(VrlNull{}) }
			new_val := set_nested(existing, rest, value)!
			mut result := c.clone_map()
			result.set(key, new_val)
			return VrlValue(result)
		}
		[]VrlValue {
			s := seg
			// Check if the segment is a non-numeric string - treat as object key
			is_string_key := match s {
				string {
					!(s.len > 0 && (s[0].is_digit() || (s[0] == `-` && s.len > 1)))
				}
				else { false }
			}
			if is_string_key {
				// Convert to object-based set
				mut obj := new_object_map()
				sk := s as string
				new_val := set_nested(VrlValue(VrlNull{}), rest, value)!
				obj.set(sk, new_val)
				return VrlValue(obj)
			}
			idx := match s {
				i64 { s }
				string { s.int() }
				else { return container }
			}
			actual_idx := if idx < 0 { c.len + idx } else { idx }
			if rest.len == 0 {
				mut result := c.clone()
				for result.len <= actual_idx {
					result << VrlValue(VrlNull{})
				}
				if actual_idx >= 0 && actual_idx < result.len {
					result[actual_idx] = value
				}
				return VrlValue(result)
			}
			existing := if actual_idx >= 0 && actual_idx < c.len { c[actual_idx] } else { VrlValue(VrlNull{}) }
			new_val := set_nested(existing, rest, value)!
			mut result := c.clone()
			for result.len <= actual_idx {
				result << VrlValue(VrlNull{})
			}
			if actual_idx >= 0 {
				result[actual_idx] = new_val
			}
			return VrlValue(result)
		}
		VrlNull {
			// Auto-create structure
			s := seg
			match s {
				string {
					mut obj := new_object_map()
					new_val := set_nested(VrlValue(VrlNull{}), rest, value)!
					obj.set(s, new_val)
					return VrlValue(obj)
				}
				i64 {
					mut arr := []VrlValue{}
					idx := if s < 0 { 0 } else { s }
					for arr.len <= idx {
						arr << VrlValue(VrlNull{})
					}
					new_val := set_nested(VrlValue(VrlNull{}), rest, value)!
					arr[idx] = new_val
					return VrlValue(arr)
				}
				else { return value }
			}
		}
		else { return value }
	}
}

fn fn_unique(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('unique requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue {
			mut result := []VrlValue{}
			for item in a {
				mut found := false
				for existing in result {
					if values_equal(item, existing) { found = true; break }
				}
				if !found { result << item }
			}
			return VrlValue(result)
		}
		else { return error('unique requires an array') }
	}
}

fn fn_to_regex(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_regex requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(VrlRegex{pattern: a}) }
		VrlRegex { return VrlValue(a) }
		else { return error('to_regex requires a string') }
	}
}

fn fn_from_unix_timestamp(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('from_unix_timestamp requires 1 argument') }
	a := args[0]
	match a {
		i64 {
			unit := if args.len > 1 {
				u := args[1]
				match u { string { u } else { 'seconds' } }
			} else { 'seconds' }
			match unit {
				'seconds' {
					t := time.unix(a)
					return VrlValue(Timestamp{t: t})
				}
				'milliseconds' {
					secs := a / 1000
					micro := (a % 1000) * 1000
					t := time.unix_microsecond(int(secs), int(micro))
					return VrlValue(Timestamp{t: t})
				}
				'microseconds' {
					secs := a / 1_000_000
					micro := a % 1_000_000
					t := time.unix_microsecond(int(secs), int(micro))
					return VrlValue(Timestamp{t: t})
				}
				'nanoseconds' {
					secs := a / 1_000_000_000
					micro := (a % 1_000_000_000) / 1000
					t := time.unix_microsecond(int(secs), int(micro))
					return VrlValue(Timestamp{t: t})
				}
				else {
					return error('unknown unit: ${unit}')
				}
			}
		}
		else { return error('from_unix_timestamp requires an integer') }
	}
}

fn fn_format_number(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('format_number requires 1 argument') }
	a := args[0]
	val := match a {
		f64 { a }
		i64 { f64(a) }
		else { return error('format_number requires a number') }
	}
	scale := if args.len > 1 { get_int_arg(args[1], -1) } else { -1 }
	decimal_sep := if args.len > 2 {
		s := args[2]
		match s { string { s } else { '.' } }
	} else { '.' }
	grouping_sep := if args.len > 3 {
		s := args[3]
		match s { string { s } else { '' } }
	} else { '' }

	// Format the number
	mut num_str := if scale >= 0 {
		format_float_precision(val, scale)
	} else {
		format_float(val)
	}

	// Split into integer and decimal parts
	mut int_part := num_str
	mut dec_part := ''
	dot_idx := num_str.index('.') or { -1 }
	if dot_idx >= 0 {
		int_part = num_str[..dot_idx]
		dec_part = num_str[dot_idx + 1..]
	} else if scale > 0 {
		dec_part = '0'.repeat(scale)
	}

	// Apply grouping separator to integer part
	if grouping_sep.len > 0 && int_part.len > 3 {
		mut grouped := []u8{}
		mut count := 0
		for i := int_part.len - 1; i >= 0; i-- {
			if count > 0 && count % 3 == 0 && int_part[i] != `-` {
				for c in grouping_sep {
					grouped << c
				}
			}
			grouped << int_part[i]
			count++
		}
		// Reverse
		mut reversed := []u8{cap: grouped.len}
		for i := grouped.len - 1; i >= 0; i-- {
			reversed << grouped[i]
		}
		int_part = reversed.bytestr()
	}

	if dec_part.len > 0 {
		return VrlValue(int_part + decimal_sep + dec_part)
	}
	return VrlValue(int_part)
}

fn format_float_precision(val f64, precision int) string {
	if precision == 0 {
		return '${int(val)}'
	}
	mut mult := 1.0
	for _ in 0 .. precision { mult *= 10.0 }
	rounded := math.round(val * mult) / mult
	// Use strlong to avoid scientific notation for large numbers
	s := strlong(rounded)
	// Ensure we have exactly `precision` decimal places
	dot_idx := s.index('.') or {
		return s + '.' + '0'.repeat(precision)
	}
	dec := s[dot_idx + 1..]
	if dec.len < precision {
		return s + '0'.repeat(precision - dec.len)
	}
	if dec.len > precision {
		return s[..dot_idx + 1 + precision]
	}
	return s
}

// strlong formats a float without scientific notation.
fn strlong(f f64) string {
	s := '${f}'
	// If V uses scientific notation, convert manually
	if !s.contains('e') && !s.contains('E') {
		return s
	}
	// Parse scientific notation
	mut mantissa := ''
	mut exp := 0
	e_idx := s.index_any('eE')
	if e_idx >= 0 {
		mantissa = s[..e_idx]
		exp = s[e_idx + 1..].int()
	} else {
		return s
	}
	// Build the number string
	dot_idx := mantissa.index('.') or { -1 }
	mut digits := mantissa.replace('.', '').replace('-', '')
	is_neg := f < 0

	mut dec_pos := if dot_idx >= 0 {
		if is_neg { dot_idx - 1 } else { dot_idx }
	} else {
		digits.len
	}
	dec_pos += exp

	if dec_pos >= digits.len {
		// No decimal part needed
		for digits.len < dec_pos {
			digits += '0'
		}
		result := digits
		return if is_neg { '-${result}' } else { result }
	}
	if dec_pos <= 0 {
		result := '0.${"0".repeat(-dec_pos)}${digits}'
		return if is_neg { '-${result}' } else { result }
	}
	result := '${digits[..dec_pos]}.${digits[dec_pos..]}'
	return if is_neg { '-${result}' } else { result }
}

fn fn_to_unix_timestamp(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_unix_timestamp requires 1 argument') }
	a := args[0]
	match a {
		Timestamp {
			unit := if args.len > 1 {
				u := args[1]
				match u { string { u } else { 'seconds' } }
			} else { 'seconds' }
			match unit {
				'seconds' {
					return VrlValue(i64(a.t.unix()))
				}
				'milliseconds' {
					ms := a.t.unix_micro() / 1000
					return VrlValue(i64(ms))
				}
				'microseconds' {
					us := a.t.unix_micro()
					return VrlValue(i64(us))
				}
				'nanoseconds' {
					ns := a.t.unix_micro() * 1000
					return VrlValue(i64(ns))
				}
				else {
					return error('unknown unit: ${unit}')
				}
			}
		}
		else { return error('to_unix_timestamp requires a timestamp') }
	}
}

fn fn_get_env_var(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('get_env_var requires 1 argument') }
	a := args[0]
	match a {
		string {
			val := os.getenv(a)
			if val.len == 0 {
				// Check if the env var actually exists but is empty
				return error('environment variable not found: ${a}')
			}
			return VrlValue(val)
		}
		else { return error('get_env_var requires a string') }
	}
}

fn fn_uuid_v4() !VrlValue {
	hex := '0123456789abcdef'
	mut buf := []u8{len: 36}
	for i in 0 .. 36 {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			buf[i] = `-`
		} else if i == 14 {
			buf[i] = `4`
		} else if i == 19 {
			buf[i] = hex[rand.intn(4) or { 0 } + 8]
		} else {
			buf[i] = hex[rand.intn(16) or { 0 }]
		}
	}
	return VrlValue(buf.bytestr())
}
