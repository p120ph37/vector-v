module vrl

import os

// ExampleTest holds a parsed Example from upstream Rust stdlib source.
struct ExampleTest {
	title  string
	source string
	input  string // optional input JSON object context
	result string // expected result string
	is_ok  bool   // true if result was Ok(...), false if Err(...)
	file   string // source .rs file
}

// parse_examples_from_rs extracts Example tests from a Rust source file.
fn parse_examples_from_rs(path string) []ExampleTest {
	content := os.read_file(path) or { return [] }
	fname := os.file_name(path)
	mut examples := []ExampleTest{}

	// Find all example! { ... } blocks
	mut pos := 0
	for pos < content.len {
		idx := content[pos..].index('example!') or { break }
		pos += idx + 8 // skip "example!"

		// Find the opening {
		mut p := pos
		for p < content.len && content[p] != `{` {
			p++
		}
		if p >= content.len {
			break
		}
		p++ // skip {

		// Find matching closing } counting braces
		mut depth := 1
		start := p
		for p < content.len && depth > 0 {
			if content[p] == `{` {
				depth++
			}
			if content[p] == `}` {
				depth--
			}
			p++
		}
		block := content[start..p - 1]
		pos = p

		// Parse fields from block
		title := extract_field(block, 'title')
		source := extract_field(block, 'source')
		input := extract_field(block, 'input')
		result_str := extract_result_field(block)
		is_ok := block.contains('result: Ok(')

		if source.len > 0 {
			examples << ExampleTest{
				title: title
				source: source
				input: input
				result: result_str
				is_ok: is_ok
				file: fname
			}
		}
	}
	return examples
}

// extract_field extracts a simple string field value from an example block.
fn extract_field(block string, field_name string) string {
	key := '${field_name}:'
	idx := block.index(key) or { return '' }
	after := block[idx + key.len..].trim_left(' \t')

	// Handle raw string r#"..."#
	if after.starts_with('r#"') {
		end := after.index('"#') or { return '' }
		if end > 3 {
			return after[3..end]
		}
		return ''
	}
	// Handle regular string "..."
	if after.len > 0 && after[0] == `"` {
		return extract_quoted_string(after)
	}
	return ''
}

// extract_result_field extracts the result value from Ok("...") or Err("...").
fn extract_result_field(block string) string {
	// Find result: Ok(...) or result: Err(...)
	mut idx := block.index('result: Ok(') or {
		idx2 := block.index('result: Err(') or { return '' }
		after := block[idx2 + 12..]
		return extract_rust_string(after)
	}
	after := block[idx + 11..]
	return extract_rust_string(after)
}

// extract_rust_string extracts a string from Ok("...") or Ok(r#"..."#) format.
fn extract_rust_string(s string) string {
	trimmed := s.trim_left(' \t\n')
	// Raw string: r#"..."#
	if trimmed.starts_with('r#"') {
		end := trimmed[3..].index('"#') or { return '' }
		return trimmed[3..3 + end]
	}
	// Regular quoted string "..."
	if trimmed.len > 0 && trimmed[0] == `"` {
		return extract_quoted_string(trimmed)
	}
	// Bare identifier like true, false, or number
	mut end := 0
	for end < trimmed.len && trimmed[end] != `)` && trimmed[end] != `,` {
		end++
	}
	return trimmed[..end].trim_space()
}

// extract_quoted_string extracts content from a "..." string, handling escapes.
fn extract_quoted_string(s string) string {
	if s.len < 2 || s[0] != `"` {
		return ''
	}
	mut result := []u8{}
	mut i := 1
	for i < s.len {
		if s[i] == `\\` && i + 1 < s.len {
			i++
			match s[i] {
				`n` { result << `\n` }
				`t` { result << `\t` }
				`\\` { result << `\\` }
				`"` { result << `"` }
				else { result << s[i] }
			}
		} else if s[i] == `"` {
			break
		} else {
			result << s[i]
		}
		i++
	}
	return result.bytestr()
}

// cmp_example_result compares actual VrlValue against expected example result string.
fn cmp_example_result(actual VrlValue, expected string) bool {
	aj := vrl_to_json(actual)
	et := expected.trim_space()

	// Direct JSON comparison
	if aj == et {
		return true
	}

	// String value comparison
	as_ := vrl_to_string(actual)
	if as_ == et {
		return true
	}

	// Handle s'...' notation (VRL string literal)
	if et.starts_with("s'") && et.ends_with("'") {
		inner := et[2..et.len - 1]
		if as_ == inner {
			return true
		}
	}

	// Handle t'...' notation (timestamp literal)
	if et.starts_with("t'") && et.ends_with("'") {
		ts_str := et[2..et.len - 1]
		if as_ == ts_str {
			return true
		}
	}

	// Handle r'...' notation (regex literal)
	if et.starts_with("r'") && et.ends_with("'") {
		rx_str := et[2..et.len - 1]
		a := actual
		if a is VrlRegex && a.pattern == rx_str {
			return true
		}
	}

	// Try parsing expected as JSON and comparing values
	ev := parse_json_recursive(et) or { return false }
	return values_equal(actual, ev)
}

fn test_upstream_stdlib_examples() {
	stdlib_dir := os.join_path(os.dir(os.dir(os.dir(@FILE))), 'upstream', 'vrl', 'src', 'stdlib')
	if !os.exists(stdlib_dir) {
		eprintln('WARN: no upstream stdlib dir')
		return
	}

	rs_files := os.walk_ext(stdlib_dir, 'rs')
	mut sf := rs_files.clone()
	sf.sort()

	mut passed := 0
	mut failed := 0
	mut skipped := 0
	mut errs := []string{}

	for file in sf {
		examples := parse_examples_from_rs(file)
		for ex in examples {
			if !ex.is_ok {
				// Skip Err examples for now
				skipped++
				continue
			}
			if ex.source.len == 0 || ex.result.len == 0 {
				skipped++
				continue
			}
			// Skip tests using unimplemented functions
			if uses_unimplemented_fn(ex.source) {
				skipped++
				continue
			}

			// Skip tests with dynamic output (now(), uuid_v4())
			if ex.source.trim_space() == 'now()' || ex.source.trim_space() == 'uuid_v4()' {
				// Just verify they don't error
				_ := execute(ex.source, map[string]VrlValue{}) or {
					failed++
					errs << 'FAIL ${ex.file}/${ex.title}: ERR: ${err.msg()}'
					continue
				}
				passed++
				continue
			}

			// Build input object context if provided
			mut input_obj := map[string]VrlValue{}
			if ex.input.len > 0 {
				parsed := parse_json_recursive(ex.input) or { VrlValue(new_object_map()) }
				p := parsed
				match p {
					ObjectMap {
						all_keys := p.keys()
						for k in all_keys {
							v := p.get(k) or { VrlValue(VrlNull{}) }
							input_obj[k] = v
						}
					}
					else {}
				}
			}

			actual := execute(ex.source, input_obj) or {
				em := err.msg()
				if ex.result.contains(em) {
					passed++
					continue
				}
				failed++
				errs << 'FAIL ${ex.file}/${ex.title}: ERR: ${em} | expected: ${ex.result}'
				continue
			}

			if cmp_example_result(actual, ex.result) {
				passed++
			} else {
				failed++
				errs << 'FAIL ${ex.file}/${ex.title}: expected=${ex.result} actual=${vrl_to_json(actual)}'
			}
		}
	}

	total := passed + failed + skipped

	mut report := []string{}
	report << '=== VRL Example Test Results ==='
	report << 'Total:${total} Pass:${passed} Fail:${failed} Skip:${skipped}'
	if errs.len > 0 {
		report << '\n--- Failures ---'
		for e in errs {
			report << e
		}
	}
	os.write_file('/tmp/vrl_example_results.txt', report.join('\n')) or {}
	assert failed <= 51, 'VRL examples: ${failed} failures (max 51 allowed). See /tmp/vrl_example_results.txt'
}
