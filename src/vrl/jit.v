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

// C trampoline for calling JIT'd function pointers
fn C.jit_call_eval(fn_ptr voidptr, in_json &char, in_len int, out_json &char, out_cap int) int

// JitProgram holds a compiled VRL program ready for native execution.
pub struct JitProgram {
pub:
	c_source string // retained for debugging
mut:
	tcc_state voidptr // &C.TCCState, kept as voidptr for non-jit builds
	eval_fn   voidptr // function pointer to jit_eval
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

		return JitProgram{
			c_source: c_source
			tcc_state: voidptr(state)
			eval_fn: eval_fn
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

		// Serialize input object to JSON
		in_json := vrl_to_json(VrlValue(obj))
		in_bytes := in_json.bytes()

		// Allocate output buffer
		out_cap := 256 * 1024 // 256KB
		mut out_buf := []u8{len: out_cap}

		// Call the JIT'd function
		out_len := C.jit_call_eval(
			prog.eval_fn,
			&char(in_bytes.data),
			in_bytes.len,
			&char(out_buf.data),
			out_cap
		)

		if out_len < 0 {
			return error('JIT: execution failed')
		}

		// Parse output JSON back to VrlValue
		out_json := unsafe { tos(out_buf.data, out_len) }
		result := parse_json_value(out_json)!

		// Extract the map
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
