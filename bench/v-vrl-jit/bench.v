module main

import time
import vrl
import os

fn run_benchmark_jit(name string, source string, input map[string]vrl.VrlValue, iterations int) {
	// Compile VRL to AST
	mut lex := vrl.new_lexer(source)
	tokens := lex.tokenize()
	mut parser := vrl.new_parser(tokens)
	ast := parser.parse() or {
		eprintln('Parse error for ${name}: ${err}')
		return
	}

	if !vrl.jit_can_compile(ast) {
		eprintln('${name}: AST not JIT-compatible, skipping')
		return
	}

	// JIT compile (includes C codegen + TCC compilation)
	compile_start := time.now()
	mut prog := vrl.jit_compile(ast) or {
		eprintln('JIT compile error for ${name}: ${err}')
		return
	}
	compile_elapsed := time.since(compile_start)
	compile_ms := f64(compile_elapsed) / 1_000_000.0
	println('${name} JIT compile: ${compile_ms:.3}ms')

	// Warm up
	for _ in 0 .. 100 {
		vrl.jit_execute(&prog, input) or { continue }
	}

	// Benchmark
	start := time.now()
	for _ in 0 .. iterations {
		vrl.jit_execute(&prog, input) or { continue }
	}
	elapsed := time.since(start)
	elapsed_ms := f64(elapsed) / 1_000_000.0
	per_iter_ns := elapsed / iterations
	println('${name}: ${iterations} iterations in ${elapsed_ms:.3}ms (${per_iter_ns} ns/iter)')

	vrl.jit_free(mut prog)
}

fn run_benchmark_interp(name string, source string, input map[string]vrl.VrlValue, iterations int) {
	// Compile once (interpreter path for comparison)
	mut lex := vrl.new_lexer(source)
	tokens := lex.tokenize()
	mut parser := vrl.new_parser(tokens)
	ast := parser.parse() or {
		eprintln('Parse error for ${name}: ${err}')
		return
	}

	// Warm up
	for _ in 0 .. 100 {
		mut rt := vrl.new_runtime_with_object(input)
		rt.eval(ast) or { continue }
	}

	// Benchmark
	start := time.now()
	for _ in 0 .. iterations {
		mut rt := vrl.new_runtime_with_object(input)
		rt.eval(ast) or { continue }
	}
	elapsed := time.since(start)
	elapsed_ms := f64(elapsed) / 1_000_000.0
	per_iter_ns := elapsed / iterations
	println('${name}: ${iterations} iterations in ${elapsed_ms:.3}ms (${per_iter_ns} ns/iter)')
}

fn main() {
	iterations := if os.args.len > 1 { os.args[1].int() } else { 100_000 }

	if !vrl.jit_available() {
		eprintln('ERROR: JIT not available. Compile with: v -d jit -o bench bench/v-vrl-jit/bench.v')
		return
	}

	// Define benchmark scenarios (same as the other harnesses)
	mut input1 := map[string]vrl.VrlValue{}
	input1['message'] = vrl.VrlValue('hello world')

	mut input2 := map[string]vrl.VrlValue{}
	input2['message'] = vrl.VrlValue('HELLO WORLD')

	mut input3 := map[string]vrl.VrlValue{}
	input3['message'] = vrl.VrlValue('error: something broke')
	input3['level'] = vrl.VrlValue('info')

	mut input4 := map[string]vrl.VrlValue{}
	input4['message'] = vrl.VrlValue('Hello World')
	input4['host'] = vrl.VrlValue('SERVER01')

	mut input5 := map[string]vrl.VrlValue{}
	input5['a'] = vrl.VrlValue(42)
	input5['b'] = vrl.VrlValue(13)

	src_field_assign := '.environment = "production"'
	src_downcase := '.message = downcase(.message)'
	src_conditional := '
		if contains(.message, "error") {
			.level = "error"
			.is_error = true
		} else {
			.level = "info"
			.is_error = false
		}
	'
	src_multi_ops := '
		.message = downcase(.message)
		.host = downcase(.host)
		.env = "production"
		.processed = true
		del(.timestamp)
	'
	src_arithmetic := '
		.sum = .a + .b
		.diff = .a - .b
		.prod = .a * .b
	'

	// --- JIT benchmarks ---
	println('=== V-lang VRL JIT Benchmark (${iterations} iterations) ===\n')

	run_benchmark_jit('field_assign', src_field_assign, input1, iterations)
	run_benchmark_jit('downcase', src_downcase, input2, iterations)
	run_benchmark_jit('conditional', src_conditional, input3, iterations)
	run_benchmark_jit('multi_ops', src_multi_ops, input4, iterations)
	run_benchmark_jit('arithmetic', src_arithmetic, input5, iterations)

	// --- Interpreter benchmarks (for side-by-side comparison) ---
	println('\n=== V-lang VRL Interpreter Benchmark (${iterations} iterations) ===\n')

	run_benchmark_interp('field_assign', src_field_assign, input1, iterations)
	run_benchmark_interp('downcase', src_downcase, input2, iterations)
	run_benchmark_interp('conditional', src_conditional, input3, iterations)
	run_benchmark_interp('multi_ops', src_multi_ops, input4, iterations)
	run_benchmark_interp('arithmetic', src_arithmetic, input5, iterations)
}
