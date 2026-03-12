module vrl

fn test_replace_with_captures() {
	// Test replace_with with regex capture groups
	// Pattern ([fg])\w\w matches 3-letter words starting with f or g
	// The closure receives a match object with .string (full match) and .captures (capture groups)
	// captures[0] is the first capture group ([fg])
	r := execute('replace_with("foo bar faa fee fo fum gum", r\'([fg])\\w\\w\') -> |m| { upcase(string!(m.captures[0])) }', map[string]VrlValue{}) or {
		assert false, 'replace_with with captures failed: ${err}'
		return
	}
	assert r == VrlValue('F bar F F fo F G'), 'expected "F bar F F fo F G", got: ${r}'
}

fn test_replace_with_multiple_captures() {
	r := execute('replace_with("foo", r\'(f)(o)(o)\') -> |m| { upcase(string!(m.captures[0])) + string!(m.captures[1]) + string!(m.captures[2]) }', map[string]VrlValue{}) or {
		assert false, 'replace_with with multiple captures failed: ${err}'
		return
	}
	assert r == VrlValue('Foo'), 'expected "Foo", got: ${r}'
}

fn test_replace_with_match_string() {
	r := execute('replace_with("foo bar", r\'\\w+\') -> |m| { upcase(m.string) }', map[string]VrlValue{}) or {
		assert false, 'replace_with with match string failed: ${err}'
		return
	}
	assert r == VrlValue('FOO BAR'), 'expected "FOO BAR", got: ${r}'
}
