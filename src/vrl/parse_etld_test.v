module vrl

fn test_parse_etld_basic() {
	result := fn_parse_etld([VrlValue('vector.dev')], map[string]VrlValue{}) or {
		panic(err.msg())
	}
	obj := result as ObjectMap
	assert (obj.get('etld') or { panic('no etld') }) == VrlValue('dev')
	assert (obj.get('known_suffix') or { panic('no known_suffix') }) == VrlValue(true)
}

fn test_parse_etld_plus_one() {
	named := {
		'plus_parts': VrlValue(i64(1))
	}
	result := fn_parse_etld([VrlValue('vector.dev')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('etld') or { panic('no etld') }) == VrlValue('dev')
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('vector.dev')
	assert (obj.get('known_suffix') or { panic('no known_suffix') }) == VrlValue(true)
}

fn test_parse_etld_plus_ten_capped() {
	named := {
		'plus_parts': VrlValue(i64(10))
	}
	result := fn_parse_etld([VrlValue('vector.dev')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('vector.dev'), 'plus_parts exceeding domain labels should cap at full domain'
}

fn test_parse_etld_multi_label_suffix() {
	named := {
		'plus_parts': VrlValue(i64(1))
	}
	result := fn_parse_etld([VrlValue('sussex.ac.uk')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('etld') or { panic('no etld') }) == VrlValue('ac.uk')
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('sussex.ac.uk')
	assert (obj.get('known_suffix') or { panic('no known_suffix') }) == VrlValue(true)
}

fn test_parse_etld_unknown_suffix() {
	result := fn_parse_etld([VrlValue('example.unknowntld')], map[string]VrlValue{}) or {
		panic(err.msg())
	}
	obj := result as ObjectMap
	assert (obj.get('etld') or { panic('no etld') }) == VrlValue('unknowntld')
	assert (obj.get('known_suffix') or { panic('no known_suffix') }) == VrlValue(false)
}

fn test_parse_etld_subdomain() {
	named := {
		'plus_parts': VrlValue(i64(1))
	}
	result := fn_parse_etld([VrlValue('www.example.com')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('etld') or { panic('no etld') }) == VrlValue('com')
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('example.com')
}

fn test_parse_etld_plus_two() {
	named := {
		'plus_parts': VrlValue(i64(2))
	}
	result := fn_parse_etld([VrlValue('www.example.com')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('www.example.com')
}

fn test_parse_etld_negative_plus_parts() {
	named := {
		'plus_parts': VrlValue(i64(-5))
	}
	result := fn_parse_etld([VrlValue('example.com')], named) or { panic(err.msg()) }
	obj := result as ObjectMap
	// Negative plus_parts treated as 0
	assert (obj.get('etld_plus') or { panic('no etld_plus') }) == VrlValue('com')
}

fn test_parse_etld_error_non_string() {
	_ := fn_parse_etld([VrlValue(i64(42))], map[string]VrlValue{}) or {
		assert err.msg().contains('string')
		return
	}
	panic('expected error for non-string argument')
}
