module main

import time
import vrl
import os

fn run_benchmark(name string, source string, input map[string]vrl.VrlValue, iterations int) {
	// Compile once
	mut lex := vrl.new_lexer(source)
	tokens := lex.tokenize()
	mut parser := vrl.new_parser(tokens)
	ast := parser.parse() or {
		eprintln('Compilation error for ${name}: ${err}')
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

	println('=== V-lang VRL Benchmark (${iterations} iterations) ===\n')

	// Benchmark 1: Simple field assignment
	mut input1 := map[string]vrl.VrlValue{}
	input1['message'] = vrl.VrlValue('hello world')
	run_benchmark('field_assign', '.environment = "production"', input1, iterations)

	// Benchmark 2: String manipulation
	mut input2 := map[string]vrl.VrlValue{}
	input2['message'] = vrl.VrlValue('HELLO WORLD')
	run_benchmark('downcase', '.message = downcase(.message)', input2, iterations)

	// Benchmark 3: Conditional logic
	mut input3 := map[string]vrl.VrlValue{}
	input3['message'] = vrl.VrlValue('error: something broke')
	input3['level'] = vrl.VrlValue('info')
	run_benchmark('conditional', '
		if contains(.message, "error") {
			.level = "error"
			.is_error = true
		} else {
			.level = "info"
			.is_error = false
		}
	', input3, iterations)

	// Benchmark 4: Multiple operations
	mut input4 := map[string]vrl.VrlValue{}
	input4['message'] = vrl.VrlValue('Hello World')
	input4['host'] = vrl.VrlValue('SERVER01')
	run_benchmark('multi_ops', '
		.message = downcase(.message)
		.host = downcase(.host)
		.env = "production"
		.processed = true
		del(.timestamp)
	', input4, iterations)

	// Benchmark 5: Arithmetic
	mut input5 := map[string]vrl.VrlValue{}
	input5['a'] = vrl.VrlValue(42)
	input5['b'] = vrl.VrlValue(13)
	run_benchmark('arithmetic', '
		.sum = .a + .b
		.diff = .a - .b
		.prod = .a * .b
	', input5, iterations)
}
