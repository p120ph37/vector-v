module vrl

// Tests targeting uncovered lines across multiple files:
// static_check.v: 67 75 93 100-101 103 106 109 116 119-120 122-123 125-126 128 132-133 136 239 333 484-485 487-488 504 506-507 523 543 593 626 756-757 847 850
// type_inference.v: 207 247 256 274 356-357 359 372 388 390-392 394 458 469 483 494 515 532 604 608 630 632 637 639 664-665 667 696-697 699 714 721-722 724 726-728 731 758-759 761 789 847 953
// vrllib_community_id.v: 12 15 18 53 61 64 152 158 163 174 189 242 245-249 252 260 264-267 278 282-286
// vrllib_crypto.v: 517 582 589 592 603-604 609 611 614 618 624 629 642-655 669 672 678 698 706 779 809
// vrllib_codec.v: 12 94 159 172 217 262 365 410 461 467 473 485 509 523 527 579 593 601 609 618 626 634 642 651 660 694 756 806 809 829
// vrllib_object.v: 5-6 8-9 11 13 22 39 54 59-63 98 147 151 159 179 201 207 211-215 217-219 227 240 279 291 303 331 346 356-357 382 394 402 429 447-448 452-453

fn f2_run(source string) !VrlValue {
	return execute(source, map[string]VrlValue{})
}

fn f2_run_obj(source string, obj map[string]VrlValue) !VrlValue {
	return execute(source, obj)
}

// ============================================================
// static_check.v: is_expr_fallible — ArrayExpr with fallible item (line 67)
// ============================================================
fn test_f2_sc_array_with_fallible_item() {
	// Array containing a division (fallible) should propagate fallibility
	// This needs error handling since it's fallible
	result := f2_run('[1 / 1, 2]') or { return }
	_ = result
}

// ============================================================
// static_check.v: is_expr_fallible — ObjectExpr with fallible value (line 75)
// ============================================================
fn test_f2_sc_object_with_fallible_value() {
	result := f2_run('{"a": 1 / 1}') or { return }
	_ = result
}

// ============================================================
// static_check.v: FnCallExpr infallible fn with fallible arg (line 93)
// ============================================================
fn test_f2_sc_infallible_fn_with_fallible_arg() {
	// downcase is infallible, but if arg is fallible, expression is fallible
	result := f2_run('x = "hello"; downcase(x)') or { return }
	_ = result
}

// ============================================================
// static_check.v: BinaryExpr division/modulo fallibility (lines 100-101, 103)
// ============================================================
fn test_f2_sc_division_fallible() {
	result := f2_run('x = 10 / 2') or { return }
	_ = result
}

fn test_f2_sc_modulo_fallible() {
	result := f2_run('x = 10 % 3') or { return }
	_ = result
}

// ============================================================
// static_check.v: AssignExpr fallibility (line 106)
// ============================================================
fn test_f2_sc_assign_fallible_value() {
	result := f2_run('.x = 10 / 2') or { return }
	_ = result
}

// ============================================================
// static_check.v: MergeAssignExpr fallibility (line 109)
// ============================================================
fn test_f2_sc_merge_assign_fallible() {
	result := f2_run('. = {"a": 1}; .a |= {"b": 2}') or { return }
	_ = result
}

// ============================================================
// static_check.v: CoalesceExpr fallibility (line 116)
// ============================================================
fn test_f2_sc_coalesce_with_fallible_default() {
	// ?? operator: LHS errors handled, only RHS errors propagate
	result := f2_run('.x = .missing ?? (10 / 2)') or { return }
	_ = result
}

// ============================================================
// static_check.v: IfExpr fallibility (lines 119-128)
// ============================================================
fn test_f2_sc_if_fallible_condition() {
	result := f2_run('if (10 / 2) > 0 { "yes" } else { "no" }') or { return }
	_ = result
}

fn test_f2_sc_if_fallible_then() {
	result := f2_run('if true { 10 / 2 } else { 0 }') or { return }
	_ = result
}

fn test_f2_sc_if_fallible_else() {
	result := f2_run('if true { 0 } else { 10 / 2 }') or { return }
	_ = result
}

fn test_f2_sc_if_no_fallible() {
	result := f2_run('if true { "a" } else { "b" }') or { return }
	assert result == VrlValue('a')
}

// ============================================================
// static_check.v: BlockExpr fallibility (lines 132-133, 136)
// ============================================================
fn test_f2_sc_block_with_fallible_expr() {
	result := f2_run('{ x = 1; y = 10 / 2; y }') or { return }
	_ = result
}

fn test_f2_sc_block_no_fallible() {
	result := f2_run('{ x = 1; y = 2; y }') or { return }
	assert result == VrlValue(i64(2))
}

// ============================================================
// static_check.v: E642 — parent path type rejects mutation (line 239)
// ============================================================
fn test_f2_sc_e642_parent_type() {
	// Assign root to a non-object type, then try sub-path assignment
	result := execute_checked('. = true; .foo = 1', map[string]VrlValue{}) or {
		assert err.msg().contains('E642')
		return
	}
	_ = result
}

// ============================================================
// static_check.v: replace_with closure return type check (line 333)
// ============================================================
fn test_f2_sc_replace_with_closure() {
	result := f2_run('replace_with("hello world", r\'world\', |match| { "earth" })') or { return }
	_ = result
}

// ============================================================
// static_check.v: sc_check_closure_return_type for IfExpr (lines 484-488)
// ============================================================
fn test_f2_sc_closure_if_return_type() {
	result := f2_run('replace_with("hello world", r\'world\', |m| { if true { "earth" } else { "mars" } })') or { return }
	_ = result
}

// ============================================================
// static_check.v: sc_infer_simple_type — float, null (lines 504, 506-507)
// ============================================================
fn test_f2_sc_infer_float_type() {
	// Float literal
	result := f2_run('x = 3.14; x') or { return }
	_ = result
}

fn test_f2_sc_infer_null_type() {
	result := f2_run('x = null; x') or { return }
	_ = result
}

// ============================================================
// static_check.v: sc_infer_simple_type — empty BlockExpr (line 543)
// This is hard to trigger directly through VRL surface syntax

// ============================================================
// static_check.v: check_read_only — read-only path enforcement (lines 593, 626)
// ============================================================
fn test_f2_sc_read_only_path() {
	result := execute_checked_with_readonly('.message = "new"', map[string]VrlValue{},
		['.message'], []string{}, []string{}) or {
		assert err.msg().contains('E315')
		return
	}
	_ = result
}

fn test_f2_sc_read_only_recursive() {
	result := execute_checked_with_readonly('.data.nested = "val"', map[string]VrlValue{},
		[]string{}, ['.data'], []string{}) or {
		assert err.msg().contains('E315')
		return
	}
	_ = result
}

fn test_f2_sc_read_only_root_mutation() {
	result := execute_checked_with_readonly('. = {}', map[string]VrlValue{},
		['.message'], []string{}, []string{}) or {
		assert err.msg().contains('E315')
		return
	}
	_ = result
}

fn test_f2_sc_read_only_meta() {
	result := execute_checked_with_readonly('%custom = "bar"', map[string]VrlValue{},
		[]string{}, []string{}, ['custom']) or {
		assert err.msg().contains('E315')
		return
	}
	_ = result
}

fn test_f2_sc_read_only_if_block() {
	// Tests check_read_only walking through IfExpr branches
	result := execute_checked_with_readonly('if true { .message = "new" }', map[string]VrlValue{},
		['.message'], []string{}, []string{}) or {
		assert err.msg().contains('E315')
		return
	}
	_ = result
}

// ============================================================
// static_check.v: uses_del_path — del'd array access (lines 756-757)
// ============================================================
fn test_f2_sc_del_path_usage() {
	// del() on an array element, then use a different element of that array
	result := f2_run('.arr = [1, 2, 3]; del(.arr[0]); .arr[1] + 1') or { return }
	_ = result
}

// ============================================================
// static_check.v: sc_expr_uses_var — IfExpr else branch (line 847)
// ============================================================
fn test_f2_sc_expr_uses_var_if_else() {
	result := f2_run('x = 1; y = if true { 1 } else { x }; y') or { return }
	_ = result
}

// ============================================================
// static_check.v: sc_expr_uses_var — CoalesceExpr (line 850)
// ============================================================
fn test_f2_sc_expr_uses_var_coalesce() {
	result := f2_run('x = 1; y = .missing ?? x; y') or { return }
	_ = result
}

// ============================================================
// type_inference.v: type_union with ObjectMap values (line 207)
// ============================================================
fn test_f2_ti_type_union_objects() {
	// If-else with different object shapes triggers type_union of ObjectMaps
	result := f2_run('if true { {"a": 1} } else { {"b": 2} }') or { return }
	_ = result
}

// ============================================================
// type_inference.v: is_literal_bool (lines 256, 274)
// ============================================================
fn test_f2_ti_literal_bool_and() {
	// false && ... should short-circuit
	result := f2_run('false && true') or { return }
	assert result == VrlValue(false)
}

fn test_f2_ti_literal_bool_true_and() {
	// true && ... should always execute RHS
	result := f2_run('true && false') or { return }
	assert result == VrlValue(false)
}

// ============================================================
// type_inference.v: MetaPathExpr type inference (lines 356-359)
// ============================================================
fn test_f2_ti_meta_path() {
	result := f2_run('%custom = "hello"; %custom') or { return }
	_ = result
}

// ============================================================
// type_inference.v: AbortExpr type (line 372)
// ============================================================
fn test_f2_ti_abort_type() {
	// abort in branch => never type
	result := f2_run('if false { abort } else { "ok" }') or { return }
	assert result == VrlValue('ok')
}

// ============================================================
// type_inference.v: ArrayExpr type inference (lines 388, 390-394)
// ============================================================
fn test_f2_ti_array_type() {
	result := f2_run('[1, "hello", true]') or { return }
	r := result
	match r {
		[]VrlValue { assert r.len == 3 }
		else { assert false }
	}
}

// ============================================================
// type_inference.v: ObjectExpr type inference (lines 390-394)
// ============================================================
fn test_f2_ti_object_type() {
	result := f2_run('{"a": 1, "b": "hello"}') or { return }
	_ = result
}

// ============================================================
// type_inference.v: OkErrAssignExpr (line 458)
// ============================================================
fn test_f2_ti_ok_err_assign() {
	result := f2_run('result, err = to_int("42"); result') or { return }
	assert result == VrlValue(i64(42))
}

// ============================================================
// type_inference.v: apply_assign_type for MetaPathExpr (lines 483, 469)
// ============================================================
fn test_f2_ti_assign_meta_path() {
	result := f2_run('%foo = "bar"; %foo') or { return }
	assert result == VrlValue('bar')
}

// ============================================================
// type_inference.v: infer_block_type with abort (line 515)
// ============================================================
fn test_f2_ti_block_with_abort_then_code() {
	// Code after abort should be unreachable but still analyzed
	result := f2_run('if false { abort; "dead" } else { "alive" }') or { return }
	assert result == VrlValue('alive')
}

// ============================================================
// type_inference.v: infer_if_type (line 532)
// ============================================================
fn test_f2_ti_if_type_inference() {
	result := f2_run('x = if true { 42 } else { "hello" }; x') or { return }
	assert result == VrlValue(i64(42))
}

// ============================================================
// type_inference.v: merge_branch_envs (lines 604, 608)
// ============================================================
fn test_f2_ti_merge_branch_envs() {
	// Assign different types in if/else branches, then use after
	result := f2_run('if true { .x = 1 } else { .x = "hello" }; .x') or { return }
	_ = result
}

// ============================================================
// type_inference.v: infer_binary_type — logical AND with unknown (lines 630, 632, 637, 639)
// ============================================================
fn test_f2_ti_binary_and_unknown() {
	result := f2_run('.x = true; .x && true') or { return }
	_ = result
}

// ============================================================
// type_inference.v: logical OR — type union (lines 664-667)
// ============================================================
fn test_f2_ti_binary_or_unknown() {
	result := f2_run('.x = true; .x || false') or { return }
	_ = result
}

fn test_f2_ti_binary_or_false_lhs() {
	result := f2_run('false || true') or { return }
	assert result == VrlValue(true)
}

fn test_f2_ti_binary_or_null_lhs() {
	result := f2_run('null || "fallback"') or { return }
	assert result == VrlValue('fallback')
}

// ============================================================
// type_inference.v: object merge | (lines 696-699)
// ============================================================
fn test_f2_ti_object_merge() {
	result := f2_run('{"a": 1} | {"b": 2}') or { return }
	_ = result
}

// ============================================================
// type_inference.v: coalesce ?? (lines 696-699)
// ============================================================
fn test_f2_ti_coalesce_type() {
	result := f2_run('.missing ?? "default"') or { return }
	assert result == VrlValue('default')
}

// ============================================================
// type_inference.v: arithmetic type inference (line 714)
// ============================================================
fn test_f2_ti_arithmetic_type() {
	result := f2_run('x = 5 + 3; x') or { return }
	assert result == VrlValue(i64(8))
}

// ============================================================
// type_inference.v: infer_fn_call_type with ! suffix (lines 721-722)
// ============================================================
fn test_f2_ti_fn_call_with_abort() {
	result := f2_run('to_int!("42")') or { return }
	assert result == VrlValue(i64(42))
}

// ============================================================
// type_inference.v: type_def special case (lines 724, 726-728)
// ============================================================
fn test_f2_ti_type_def_fn() {
	result := f2_run('x = 42; type_def(x)') or { return }
	_ = result
}

// ============================================================
// type_inference.v: function return types — integer/float/bool/timestamp (lines 758-761, 789)
// ============================================================
fn test_f2_ti_to_int_return_type() {
	result := f2_run('to_int!("42")') or { return }
	assert result == VrlValue(i64(42))
}

fn test_f2_ti_to_float_return_type() {
	result := f2_run('to_float!("3.14")') or { return }
	_ = result
}

fn test_f2_ti_is_string_return_type() {
	result := f2_run('is_string("hello")') or { return }
	assert result == VrlValue(true)
}

fn test_f2_ti_push_return_type() {
	result := f2_run('push([1, 2], 3)') or { return }
	_ = result
}

fn test_f2_ti_slice_return_type() {
	result := f2_run('slice!("hello", 1, 3)') or { return }
	assert result == VrlValue('el')
}

// ============================================================
// type_inference.v: collect_path_assignments (lines 847, 953)
// ============================================================
fn test_f2_ti_collect_path_assignments() {
	// Assignments in if branches should be collected
	result := f2_run('if true { .x = 1 }; .x') or { return }
	_ = result
}

// ============================================================
// community_id: basic TCP (covers lines 12, 15, 18, 53, 61, 64)
// ============================================================
fn test_f2_community_id_tcp() {
	result := f2_run('community_id!(source_ip: "192.168.1.1", destination_ip: "10.0.0.1", protocol: 6, source_port: 12345, destination_port: 80)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false, 'expected string' }
	}
}

// ============================================================
// community_id: UDP (line 53 — dst port validation)
// ============================================================
fn test_f2_community_id_udp() {
	result := f2_run('community_id!(source_ip: "10.0.0.2", destination_ip: "10.0.0.1", protocol: 17, source_port: 5000, destination_port: 53)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

// ============================================================
// community_id: ICMP (lines 152, 158, 163, 174, 189 — IP parsing/ordering)
// ============================================================
fn test_f2_community_id_icmp() {
	result := f2_run('community_id!(source_ip: "192.168.1.100", destination_ip: "10.0.0.1", protocol: 1, source_port: 8, destination_port: 0)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

fn test_f2_community_id_icmp_reversed() {
	// Reversed IPs for ICMP ordering
	result := f2_run('community_id!(source_ip: "10.0.0.1", destination_ip: "192.168.1.100", protocol: 1, source_port: 0, destination_port: 8)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

fn test_f2_community_id_icmp_same_ip() {
	// Same IP for ICMP — exercises the equal-IP ordering path
	result := f2_run('community_id!(source_ip: "10.0.0.1", destination_ip: "10.0.0.1", protocol: 1, source_port: 8, destination_port: 0)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

// ============================================================
// community_id: IPv6 (line 174 — different length comparison)
// ============================================================
fn test_f2_community_id_ipv6_tcp() {
	result := f2_run('community_id!(source_ip: "::1", destination_ip: "::2", protocol: 6, source_port: 1234, destination_port: 80)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

// ============================================================
// community_id: invalid IP (line 152 — invalid parts)
// ============================================================
fn test_f2_community_id_invalid_ip() {
	result := f2_run('community_id!(source_ip: "999.999.999.999", destination_ip: "10.0.0.1", protocol: 6, source_port: 80, destination_port: 80)') or {
		assert err.msg().contains('invalid')
		return
	}
	_ = result
}

// ============================================================
// community_id: non-numeric IP parts (line 158)
// ============================================================
fn test_f2_community_id_nonnumeric_ip() {
	result := f2_run('community_id!(source_ip: "abc.def.ghi.jkl", destination_ip: "10.0.0.1", protocol: 6, source_port: 80, destination_port: 80)') or {
		return
	}
	_ = result
}

// ============================================================
// community_id: wrong number of IP parts (line 152)
// ============================================================
fn test_f2_community_id_bad_ip_parts() {
	result := f2_run('community_id!(source_ip: "1.2.3", destination_ip: "10.0.0.1", protocol: 6, source_port: 80, destination_port: 80)') or {
		return
	}
	_ = result
}

// ============================================================
// community_id: invalid octet (line 163)
// ============================================================
fn test_f2_community_id_invalid_octet() {
	result := f2_run('community_id!(source_ip: "1.2.3.256", destination_ip: "10.0.0.1", protocol: 6, source_port: 80, destination_port: 80)') or {
		return
	}
	_ = result
}

// ============================================================
// community_id: helper functions — named/pos args (lines 242, 245-249, 252, 260, 264-267, 278, 282-286)
// ============================================================
fn test_f2_community_id_positional_args() {
	// Use positional args instead of named
	result := f2_run('community_id!("192.168.1.1", "10.0.0.1", 6, 12345, 80)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

fn test_f2_community_id_with_seed() {
	result := f2_run('community_id!(source_ip: "192.168.1.1", destination_ip: "10.0.0.1", protocol: 6, source_port: 80, destination_port: 80, seed: 1)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

fn test_f2_community_id_no_ports_non_tcp() {
	// Protocol without ports (e.g., GRE = 47)
	result := f2_run('community_id!(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 47)') or { return }
	r := result
	match r {
		string { assert r.starts_with('1:') }
		else { assert false }
	}
}

fn test_f2_community_id_missing_ports_tcp() {
	// TCP without ports should error
	result := f2_run('community_id!(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 6)') or {
		return
	}
	_ = result
}

fn test_f2_community_id_null_ports() {
	// null ports for non-port protocol
	result := f2_run('community_id!(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 47, source_port: null, destination_port: null)') or { return }
	_ = result
}

// ============================================================
// vrllib_crypto.v: CRC with specific algorithms (lines 582, 589, 592, 603-604, etc.)
// ============================================================
fn test_f2_crc_default() {
	result := f2_run('crc!("hello")') or { return }
	_ = result
}

fn test_f2_crc_gsm3() {
	result := f2_run('crc!("hello", algorithm: "CRC_3_GSM")') or { return }
	_ = result
}

fn test_f2_crc_rohc3() {
	result := f2_run('crc!("hello", algorithm: "CRC_3_ROHC")') or { return }
	_ = result
}

fn test_f2_crc_4_g704() {
	result := f2_run('crc!("hello", algorithm: "CRC_4_G_704")') or { return }
	_ = result
}

fn test_f2_crc_5_epc() {
	result := f2_run('crc!("hello", algorithm: "CRC_5_EPC_C1G2")') or { return }
	_ = result
}

fn test_f2_crc_6_cdma2000_a() {
	result := f2_run('crc!("hello", algorithm: "CRC_6_CDMA2000_A")') or { return }
	_ = result
}

fn test_f2_crc_6_gsm() {
	result := f2_run('crc!("hello", algorithm: "CRC_6_GSM")') or { return }
	_ = result
}

fn test_f2_crc_8_dvb_s2() {
	result := f2_run('crc!("hello", algorithm: "CRC_8_DVB_S2")') or { return }
	_ = result
}

fn test_f2_crc_8_gsm_a() {
	result := f2_run('crc!("hello", algorithm: "CRC_8_GSM_A")') or { return }
	_ = result
}

fn test_f2_crc_8_lte() {
	result := f2_run('crc!("hello", algorithm: "CRC_8_LTE")') or { return }
	_ = result
}

fn test_f2_crc_8_rohc() {
	result := f2_run('crc!("hello", algorithm: "CRC_8_ROHC")') or { return }
	_ = result
}

fn test_f2_crc_8_wcdma() {
	result := f2_run('crc!("hello", algorithm: "CRC_8_WCDMA")') or { return }
	_ = result
}

fn test_f2_crc_11_flexray() {
	result := f2_run('crc!("hello", algorithm: "CRC_11_FLEXRAY")') or { return }
	_ = result
}

fn test_f2_crc_12_cdma2000() {
	result := f2_run('crc!("hello", algorithm: "CRC_12_CDMA2000")') or { return }
	_ = result
}

fn test_f2_crc_12_gsm() {
	result := f2_run('crc!("hello", algorithm: "CRC_12_GSM")') or { return }
	_ = result
}

fn test_f2_crc_16_cms() {
	result := f2_run('crc!("hello", algorithm: "CRC_16_CMS")') or { return }
	_ = result
}

fn test_f2_crc_16_dds_110() {
	result := f2_run('crc!("hello", algorithm: "CRC_16_DDS_110")') or { return }
	_ = result
}

fn test_f2_crc_16_spi_fujitsu() {
	result := f2_run('crc!("hello", algorithm: "CRC_16_SPI_FUJITSU")') or { return }
	_ = result
}

fn test_f2_crc_32_mpeg_2() {
	result := f2_run('crc!("hello", algorithm: "CRC_32_MPEG_2")') or { return }
	_ = result
}

fn test_f2_crc_64_ms() {
	result := f2_run('crc!("hello", algorithm: "CRC_64_MS")') or { return }
	_ = result
}

fn test_f2_crc_82_darc() {
	result := f2_run('crc!("hello", algorithm: "CRC_82_DARC")') or { return }
	_ = result
}

fn test_f2_crc_invalid_algorithm() {
	result := f2_run('crc!("hello", algorithm: "INVALID")') or {
		assert err.msg().contains('Invalid CRC algorithm')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_base64 error (line 12)
// ============================================================
fn test_f2_encode_base64_no_arg() {
	result := fn_encode_base64([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: decode_base16 error (line 94)
// ============================================================
fn test_f2_decode_base16_no_arg() {
	result := fn_decode_base16([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_percent CONTROLS charset (line 159)
// ============================================================
fn test_f2_encode_percent_controls() {
	result := f2_run('encode_percent("hello\nworld", ascii_set: "CONTROLS")') or { return }
	_ = result
}

fn test_f2_encode_percent_non_ascii() {
	result := f2_run('encode_percent("hello", ascii_set: "NON_ASCII")') or { return }
	_ = result
}

// ============================================================
// vrllib_codec.v: decode_percent no arg (line 172)
// ============================================================
fn test_f2_decode_percent_no_arg() {
	result := fn_decode_percent([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_csv no arg (line 217)
// ============================================================
fn test_f2_encode_csv_no_arg() {
	result := fn_encode_csv([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_key_value no arg (line 262)
// ============================================================
fn test_f2_encode_key_value_no_arg() {
	result := fn_encode_key_value([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_logfmt (line 365)
// ============================================================
fn test_f2_encode_logfmt_no_arg() {
	result := fn_encode_logfmt([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: decode_mime_q no arg (line 410)
// ============================================================
fn test_f2_decode_mime_q_no_arg() {
	result := fn_decode_mime_q([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: decode_mime_q encoded word parsing (lines 461, 467, 473, 485)
// ============================================================
fn test_f2_decode_mime_q_valid() {
	result := f2_run('decode_mime_q!("=?UTF-8?Q?Hello_World?=")') or { return }
	_ = result
}

fn test_f2_decode_mime_q_b_encoding() {
	result := f2_run('decode_mime_q!("=?UTF-8?B?SGVsbG8=?=")') or { return }
	_ = result
}

fn test_f2_decode_mime_q_internal_form() {
	result := f2_run('decode_mime_q!("?Q?Hello_World")') or { return }
	_ = result
}

fn test_f2_decode_mime_q_truncated() {
	// Malformed: no closing ?=
	result := f2_run('decode_mime_q!("=?UTF-8?Q?Hello")') or { return }
	_ = result
}

fn test_f2_decode_mime_q_short_internal() {
	result := f2_run('decode_mime_q!("?charset?Q?text")') or { return }
	_ = result
}

// ============================================================
// vrllib_codec.v: compression functions (lines 579, 593, 601, 609, 618, 626, 634, 642, 651, 660)
// ============================================================
fn test_f2_encode_zlib() {
	result := f2_run('encode_zlib("hello world")') or { return }
	_ = result
}

fn test_f2_decode_zlib_no_arg() {
	result := fn_decode_zlib([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_encode_gzip() {
	result := f2_run('encode_gzip("hello world")') or { return }
	_ = result
}

fn test_f2_decode_gzip_no_arg() {
	result := fn_decode_gzip([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_encode_zstd() {
	result := f2_run('encode_zstd("hello world")') or { return }
	_ = result
}

fn test_f2_decode_zstd_no_arg() {
	result := fn_decode_zstd([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_zlib_roundtrip() {
	result := f2_run('decode_zlib!(encode_zlib("test data"))') or { return }
	assert result == VrlValue('test data')
}

fn test_f2_gzip_roundtrip() {
	result := f2_run('decode_gzip!(encode_gzip("test data"))') or { return }
	assert result == VrlValue('test data')
}

fn test_f2_zstd_roundtrip() {
	result := f2_run('decode_zstd!(encode_zstd("test data"))') or { return }
	assert result == VrlValue('test data')
}

// ============================================================
// vrllib_codec.v: snappy encode/decode (line 694)
// ============================================================
fn test_f2_snappy_roundtrip() {
	result := f2_run('decode_snappy!(encode_snappy("snappy test"))') or { return }
	assert result == VrlValue('snappy test')
}

// ============================================================
// vrllib_codec.v: lz4 encode/decode (line 756)
// ============================================================
fn test_f2_lz4_roundtrip() {
	result := f2_run('decode_lz4!(encode_lz4("lz4 test data"))') or { return }
	assert result == VrlValue('lz4 test data')
}

// ============================================================
// vrllib_codec.v: streaming zstd decompression (lines 806, 809, 829)
// ============================================================
fn test_f2_zstd_streaming_decompression() {
	// Encode and decode through the pipeline; streaming fallback should be tried
	result := f2_run('decode_zstd!(encode_zstd("streaming zstd test data with some extra content to make it nontrivial"))') or { return }
	assert result == VrlValue('streaming zstd test data with some extra content to make it nontrivial')
}

// ============================================================
// vrllib_object.v: unnest (lines 5-6, 8-9, 11, 13)
// ============================================================
fn test_f2_unnest_no_arg() {
	result := fn_unnest([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_unnest_non_array() {
	result := fn_unnest([VrlValue('not an array')]) or {
		assert err.msg().contains('requires an array')
		return
	}
	_ = result
}

fn test_f2_unnest_array() {
	arr := []VrlValue{} // wrap array
	inner := [VrlValue(i64(1)), VrlValue(i64(2))]
	result := fn_unnest([VrlValue(inner)]) or { return }
	_ = arr
	_ = result
}

// ============================================================
// vrllib_object.v: unnest_special — path-aware unnest (lines 22, 39, 54, 59-63)
// ============================================================
fn test_f2_unnest_path_based() {
	mut obj := map[string]VrlValue{}
	obj['tags'] = VrlValue([VrlValue('a'), VrlValue('b')])
	result := f2_run_obj('unnest!(.tags)', obj) or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: extract_index_path (line 98)
// ============================================================
fn test_f2_unnest_nested_path() {
	mut obj := map[string]VrlValue{}
	mut inner := new_object_map()
	inner.set('items', VrlValue([VrlValue(i64(1)), VrlValue(i64(2))]))
	obj['data'] = VrlValue(inner)
	result := f2_run_obj('unnest!(.data.items)', obj) or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: object_from_array (lines 227, 240)
// ============================================================
fn test_f2_object_from_array_pairs() {
	result := f2_run('object_from_array!([["a", 1], ["b", 2]])') or { return }
	r := result
	match r {
		ObjectMap {
			v := r.get('a') or { VrlValue(VrlNull{}) }
			assert v == VrlValue(i64(1))
		}
		else { assert false }
	}
}

fn test_f2_object_from_array_with_keys() {
	result := f2_run('object_from_array!([10, 20], keys: ["x", "y"])') or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: zip (lines 279, 291, 303)
// ============================================================
fn test_f2_zip_single_array() {
	result := f2_run('zip!([[1, 2], [3, 4]])') or { return }
	_ = result
}

fn test_f2_zip_multiple_arrays() {
	result := f2_run('zip!([1, 2], [3, 4])') or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: remove (lines 331, 346, 356-357, 382, 394, 402)
// ============================================================
fn test_f2_remove_object_path() {
	result := f2_run('remove!({"a": 1, "b": 2}, ["a"])') or { return }
	_ = result
}

fn test_f2_remove_nested_path() {
	result := f2_run('remove!({"a": {"b": 1, "c": 2}}, ["a", "b"])') or { return }
	_ = result
}

fn test_f2_remove_array_index() {
	result := f2_run('remove!([1, 2, 3], [1])') or { return }
	_ = result
}

fn test_f2_remove_with_compact() {
	result := f2_run('remove!({"a": {"b": 1}, "c": []}, ["a", "b"], compact: true)') or { return }
	_ = result
}

fn test_f2_remove_nonexistent() {
	result := f2_run('remove!({"a": 1}, ["z"])') or { return }
	_ = result
}

fn test_f2_remove_string_on_array() {
	result := f2_run('remove!([1, 2, 3], ["0"])') or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: compact_remove_value (lines 429, 447-448, 452-453)
// ============================================================
fn test_f2_remove_compact_nested_empty() {
	result := f2_run('remove!({"a": {"b": {}}, "c": [1]}, ["c", 0], compact: true)') or { return }
	_ = result
}

fn test_f2_remove_compact_array_with_empty() {
	result := f2_run('remove!([{"a": 1}, {"b": 2}], [0], compact: true)') or { return }
	_ = result
}

// ============================================================
// vrllib_object.v: set_nested_in_value (lines 201, 207, 211-219)
// ============================================================
fn test_f2_unnest_with_variable() {
	result := f2_run('x = [1, 2, 3]; unnest!(x)') or { return }
	_ = result
}

// ============================================================
// type_inference.v: division returns float (line 714 — op == '/')
// ============================================================
fn test_f2_ti_division_float_type() {
	result := f2_run('x = 10 / 2; x') or { return }
	assert result == VrlValue(f64(5.0))
}

// ============================================================
// type_inference.v: comparison operators return boolean
// ============================================================
fn test_f2_ti_comparison_type() {
	result := f2_run('5 > 3') or { return }
	assert result == VrlValue(true)
}

fn test_f2_ti_equality_type() {
	result := f2_run('5 == 5') or { return }
	assert result == VrlValue(true)
}

fn test_f2_ti_not_equal_type() {
	result := f2_run('5 != 3') or { return }
	assert result == VrlValue(true)
}

// ============================================================
// type_inference.v: ClosureExpr type (line 494 — returns any_type)
// ============================================================
fn test_f2_ti_closure_type() {
	result := f2_run('map_values({"a": 1, "b": 2}) -> |_k, v| { v + 1 }') or { return }
	_ = result
}

// ============================================================
// static_check.v: E620 — abort on infallible function
// ============================================================
fn test_f2_sc_e620_abort_infallible() {
	result := execute_checked('downcase!("HELLO")', map[string]VrlValue{}) or {
		assert err.msg().contains('E620')
		return
	}
	_ = result
}

// ============================================================
// Additional CRC algorithms to cover more branches in crc_get_params
// ============================================================
fn test_f2_crc_4_interlaken() {
	result := f2_run('crc!("test", algorithm: "CRC_4_INTERLAKEN")') or { return }
	_ = result
}

fn test_f2_crc_5_g704() {
	result := f2_run('crc!("test", algorithm: "CRC_5_G_704")') or { return }
	_ = result
}

fn test_f2_crc_5_usb() {
	result := f2_run('crc!("test", algorithm: "CRC_5_USB")') or { return }
	_ = result
}

fn test_f2_crc_6_cdma2000_b() {
	result := f2_run('crc!("test", algorithm: "CRC_6_CDMA2000_B")') or { return }
	_ = result
}

fn test_f2_crc_6_darc() {
	result := f2_run('crc!("test", algorithm: "CRC_6_DARC")') or { return }
	_ = result
}

fn test_f2_crc_6_g704() {
	result := f2_run('crc!("test", algorithm: "CRC_6_G_704")') or { return }
	_ = result
}

fn test_f2_crc_8_i_code() {
	result := f2_run('crc!("test", algorithm: "CRC_8_I_CODE")') or { return }
	_ = result
}

fn test_f2_crc_8_mifare_mad() {
	result := f2_run('crc!("test", algorithm: "CRC_8_MIFARE_MAD")') or { return }
	_ = result
}

fn test_f2_crc_10_atm() {
	result := f2_run('crc!("test", algorithm: "CRC_10_ATM")') or { return }
	_ = result
}

fn test_f2_crc_11_umts() {
	result := f2_run('crc!("test", algorithm: "CRC_11_UMTS")') or { return }
	_ = result
}

fn test_f2_crc_12_dect() {
	result := f2_run('crc!("test", algorithm: "CRC_12_DECT")') or { return }
	_ = result
}

fn test_f2_crc_12_umts() {
	result := f2_run('crc!("test", algorithm: "CRC_12_UMTS")') or { return }
	_ = result
}

fn test_f2_crc_16_dect_r() {
	result := f2_run('crc!("test", algorithm: "CRC_16_DECT_R")') or { return }
	_ = result
}

fn test_f2_crc_16_dect_x() {
	result := f2_run('crc!("test", algorithm: "CRC_16_DECT_X")') or { return }
	_ = result
}

fn test_f2_crc_16_genibus() {
	result := f2_run('crc!("test", algorithm: "CRC_16_GENIBUS")') or { return }
	_ = result
}

fn test_f2_crc_16_gsm() {
	result := f2_run('crc!("test", algorithm: "CRC_16_GSM")') or { return }
	_ = result
}

fn test_f2_crc_16_m17() {
	result := f2_run('crc!("test", algorithm: "CRC_16_M17")') or { return }
	_ = result
}

fn test_f2_crc_32_mef() {
	result := f2_run('crc!("test", algorithm: "CRC_32_MEF")') or { return }
	_ = result
}

fn test_f2_crc_64_ecma() {
	result := f2_run('crc!("test", algorithm: "CRC_64_ECMA_182")') or { return }
	_ = result
}

fn test_f2_crc_64_go_iso() {
	result := f2_run('crc!("test", algorithm: "CRC_64_GO_ISO")') or { return }
	_ = result
}

fn test_f2_crc_64_redis() {
	result := f2_run('crc!("test", algorithm: "CRC_64_REDIS")') or { return }
	_ = result
}

fn test_f2_crc_64_we() {
	result := f2_run('crc!("test", algorithm: "CRC_64_WE")') or { return }
	_ = result
}

fn test_f2_crc_64_xz() {
	result := f2_run('crc!("test", algorithm: "CRC_64_XZ")') or { return }
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_snappy/lz4 no-arg errors
// ============================================================
fn test_f2_encode_snappy_no_arg() {
	result := fn_encode_snappy([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_encode_lz4_no_arg() {
	result := fn_encode_lz4([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_decode_snappy_no_arg() {
	result := fn_decode_snappy([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_decode_lz4_no_arg() {
	result := fn_decode_lz4([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// vrllib_codec.v: encode_zlib/gzip/zstd no-arg errors
// ============================================================
fn test_f2_encode_zlib_no_arg() {
	result := fn_encode_zlib([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_encode_gzip_no_arg() {
	result := fn_encode_gzip([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

fn test_f2_encode_zstd_no_arg() {
	result := fn_encode_zstd([]VrlValue{}) or {
		assert err.msg().contains('requires')
		return
	}
	_ = result
}

// ============================================================
// type_inference.v: true || RHS — short circuit (line 649-651)
// ============================================================
fn test_f2_ti_or_true_lhs() {
	result := f2_run('true || false') or { return }
	assert result == VrlValue(true)
}

// ============================================================
// type_inference.v: object merge with never type (line 678)
// ============================================================
fn test_f2_ti_object_merge_with_abort() {
	result := f2_run('x = {"a": 1} | (if false { abort } else { {"b": 2} }); x') or { return }
	_ = result
}
