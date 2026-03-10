module vrl

// JIT compilation of VRL programs using libtcc.
//
// Enabled with: v -d jit -o vector-v src/
//
// When compiled without -d jit, all JIT functions return errors gracefully,
// and the interpreter path is used instead.

$if jit ? {
	#flag -ltcc
	#include <libtcc.h>
	#flag -I @VMODROOT/src/vrl
	#include "jit_call.h"
}

// libtcc FFI declarations (only active when compiled with -d jit)
struct C.TCCState {}

fn C.tcc_new() &C.TCCState
fn C.tcc_delete(s &C.TCCState)
fn C.tcc_set_output_type(s &C.TCCState, output_type int)
fn C.tcc_compile_string(s &C.TCCState, buf &char) int
fn C.tcc_relocate(s &C.TCCState, ptr voidptr) int
fn C.tcc_get_symbol(s &C.TCCState, name &char) voidptr
fn C.tcc_set_options(s &C.TCCState, str &char)
fn C.tcc_add_sysinclude_path(s &C.TCCState, pathname &char) int
fn C.tcc_set_lib_path(s &C.TCCState, path &char)
fn C.tcc_add_library_path(s &C.TCCState, pathname &char) int

// C trampolines for calling JIT'd function pointers
fn C.jit_call_eval(fn_ptr voidptr, in_json &char, in_len int, out_json &char, out_cap int) int
fn C.jit_call_init(fp voidptr)
fn C.jit_call_set_str(fp voidptr, k &char, v &char, vl int)
fn C.jit_call_set_int(fp voidptr, k &char, v i64)
fn C.jit_call_set_float(fp voidptr, k &char, v f64)
fn C.jit_call_set_bool(fp voidptr, k &char, v int)
fn C.jit_call_eval_direct(fp voidptr) int
fn C.jit_call_result_len(fp voidptr) int
fn C.jit_call_result_key(fp voidptr, i int) &char
fn C.jit_call_result_type(fp voidptr, i int) int
fn C.jit_call_result_str_ptr(fp voidptr, i int) &char
fn C.jit_call_result_str_len(fp voidptr, i int) int
fn C.jit_call_result_int_val(fp voidptr, i int) i64
fn C.jit_call_result_float_val(fp voidptr, i int) f64
fn C.jit_call_result_bool_val(fp voidptr, i int) int
fn C.jit_call_result_json(fp voidptr, i int, buf &char, cap int) int

// JitProgram holds a compiled VRL program ready for native execution.
pub struct JitProgram {
pub:
	c_source string // retained for debugging
mut:
	tcc_state    voidptr // &C.TCCState, kept as voidptr for non-jit builds
	eval_fn      voidptr // function pointer to jit_eval (legacy JSON)
	// Direct interface function pointers (no JSON round-trip)
	fn_init      voidptr
	fn_set_str   voidptr
	fn_set_int   voidptr
	fn_set_float voidptr
	fn_set_bool  voidptr
	fn_eval      voidptr // jit_eval_direct
	fn_res_len   voidptr
	fn_res_key   voidptr
	fn_res_type  voidptr
	fn_res_sptr  voidptr
	fn_res_slen  voidptr
	fn_res_ival  voidptr
	fn_res_fval  voidptr
	fn_res_bval  voidptr
	fn_res_json  voidptr
}

// jit_compile compiles a VRL AST into a native JIT program.
// Requires compilation with -d jit flag.
pub fn jit_compile(expr Expr) !JitProgram {
	$if jit ? {
		c_source := jit_generate_c(expr)!

		state := C.tcc_new()
		if state == unsafe { nil } {
			return error('JIT: failed to create TCC state')
		}

		C.tcc_set_output_type(state, 1) // TCC_OUTPUT_MEMORY
		C.tcc_set_options(state, c'-O2')

		// Add TCC's own include and library paths for stddef.h, libtcc1.a, etc.
		tcc_dir := '/usr/lib/x86_64-linux-gnu/tcc'
		C.tcc_set_lib_path(state, &char(tcc_dir.str))
		C.tcc_add_library_path(state, &char(tcc_dir.str))
		tcc_inc := '${tcc_dir}/include'
		C.tcc_add_sysinclude_path(state, &char(tcc_inc.str))

		if C.tcc_compile_string(state, c_source.str) == -1 {
			C.tcc_delete(state)
			return error('JIT: TCC compilation failed')
		}

		// TCC_RELOCATE_AUTO = (void*)1
		if C.tcc_relocate(state, voidptr(u64(1))) < 0 {
			C.tcc_delete(state)
			return error('JIT: TCC relocation failed')
		}

		eval_fn := C.tcc_get_symbol(state, c'jit_eval')
		if eval_fn == unsafe { nil } {
			C.tcc_delete(state)
			return error('JIT: jit_eval symbol not found')
		}

		// Look up direct interface symbols
		fn_init := C.tcc_get_symbol(state, c'jit_init')
		fn_eval_direct := C.tcc_get_symbol(state, c'jit_eval_direct')

		return JitProgram{
			c_source: c_source
			tcc_state: voidptr(state)
			eval_fn: eval_fn
			fn_init: fn_init
			fn_set_str: C.tcc_get_symbol(state, c'jit_set_str')
			fn_set_int: C.tcc_get_symbol(state, c'jit_set_int')
			fn_set_float: C.tcc_get_symbol(state, c'jit_set_float')
			fn_set_bool: C.tcc_get_symbol(state, c'jit_set_bool')
			fn_eval: fn_eval_direct
			fn_res_len: C.tcc_get_symbol(state, c'jit_result_len')
			fn_res_key: C.tcc_get_symbol(state, c'jit_result_key')
			fn_res_type: C.tcc_get_symbol(state, c'jit_result_type')
			fn_res_sptr: C.tcc_get_symbol(state, c'jit_result_str_ptr')
			fn_res_slen: C.tcc_get_symbol(state, c'jit_result_str_len')
			fn_res_ival: C.tcc_get_symbol(state, c'jit_result_int_val')
			fn_res_fval: C.tcc_get_symbol(state, c'jit_result_float_val')
			fn_res_bval: C.tcc_get_symbol(state, c'jit_result_bool_val')
			fn_res_json: C.tcc_get_symbol(state, c'jit_result_json')
		}
	} $else {
		return error('JIT not available: recompile with -d jit')
	}
}

// jit_execute runs a JIT-compiled program against an object context.
// Returns the modified object as a map after execution.
pub fn jit_execute(prog &JitProgram, obj map[string]VrlValue) !map[string]VrlValue {
	$if jit ? {
		if prog.eval_fn == unsafe { nil } {
			return error('JIT: program not compiled')
		}

		// Use direct interface if available (no JSON round-trip)
		if prog.fn_init != unsafe { nil } && prog.fn_eval != unsafe { nil } {
			return jit_execute_direct(prog, obj)
		}

		// Fallback to legacy JSON interface
		in_json := vrl_to_json(VrlValue(obj))
		out_cap := 4096
		mut out_buf := []u8{len: out_cap}

		out_len := C.jit_call_eval(
			prog.eval_fn,
			in_json.str,
			in_json.len,
			&char(out_buf.data),
			out_cap
		)

		if out_len < 0 {
			return error('JIT: execution failed')
		}

		out_json := unsafe { tos(out_buf.data, out_len) }
		result := parse_json_value(out_json)!

		r := result
		match r {
			map[string]VrlValue {
				return r
			}
			else {
				return error('JIT: result is not an object')
			}
		}
	} $else {
		return error('JIT not available: recompile with -d jit')
	}
}

// jit_execute_direct uses the direct memory interface to avoid JSON serialization.
fn jit_execute_direct(prog &JitProgram, obj map[string]VrlValue) !map[string]VrlValue {
	// Initialize context (resets arena, creates empty object)
	C.jit_call_init(prog.fn_init)

	// Set input fields
	for k, v in obj {
		val := v
		match val {
			string {
				C.jit_call_set_str(prog.fn_set_str, &char(k.str), &char(val.str), val.len)
			}
			int {
				C.jit_call_set_int(prog.fn_set_int, &char(k.str), i64(val))
			}
			f64 {
				C.jit_call_set_float(prog.fn_set_float, &char(k.str), val)
			}
			bool {
				b := if val { 1 } else { 0 }
				C.jit_call_set_bool(prog.fn_set_bool, &char(k.str), b)
			}
			else {
				// For complex types (arrays, objects, etc.), fall back to JSON
				json_str := vrl_to_json(VrlValue(v))
				C.jit_call_set_str(prog.fn_set_str, &char(k.str), &char(json_str.str), json_str.len)
			}
		}
	}

	// Execute the JIT-compiled program
	rc := C.jit_call_eval_direct(prog.fn_eval)
	if rc != 0 {
		return error('JIT: execution failed')
	}

	// Extract results directly from the JIT context
	n := C.jit_call_result_len(prog.fn_res_len)
	mut result := map[string]VrlValue{}

	for i in 0 .. n {
		key_ptr := C.jit_call_result_key(prog.fn_res_key, i)
		key := unsafe { tos_clone(&u8(key_ptr)) }
		val_type := C.jit_call_result_type(prog.fn_res_type, i)

		match val_type {
			1 {
				// VT_BOOL
				result[key] = VrlValue(C.jit_call_result_bool_val(prog.fn_res_bval, i) != 0)
			}
			2 {
				// VT_INT
				result[key] = VrlValue(int(C.jit_call_result_int_val(prog.fn_res_ival, i)))
			}
			3 {
				// VT_FLOAT
				result[key] = VrlValue(C.jit_call_result_float_val(prog.fn_res_fval, i))
			}
			4 {
				// VT_STRING
				sptr := C.jit_call_result_str_ptr(prog.fn_res_sptr, i)
				slen := C.jit_call_result_str_len(prog.fn_res_slen, i)
				result[key] = VrlValue(unsafe { tos(&u8(sptr), slen) }.clone())
			}
			5, 6 {
				// VT_ARRAY or VT_OBJECT — serialize to JSON and parse back
				mut json_buf := [4096]u8{}
				json_len := C.jit_call_result_json(prog.fn_res_json, i, &char(&json_buf[0]), 4096)
				if json_len > 0 {
					json_str := unsafe { tos(&json_buf[0], json_len) }
					val := parse_json_value(json_str) or { VrlValue(VrlNull{}) }
					result[key] = val
				}
			}
			else {
				// VT_NULL
				result[key] = VrlValue(VrlNull{})
			}
		}
	}

	return result
}

// jit_free releases resources associated with a JIT-compiled program.
pub fn jit_free(mut prog JitProgram) {
	$if jit ? {
		if prog.tcc_state != unsafe { nil } {
			unsafe { C.tcc_delete(&C.TCCState(prog.tcc_state)) }
			prog.tcc_state = unsafe { nil }
			prog.eval_fn = unsafe { nil }
		}
	}
}

// jit_available returns true if the JIT subsystem is compiled in.
pub fn jit_available() bool {
	$if jit ? {
		return true
	} $else {
		return false
	}
}
