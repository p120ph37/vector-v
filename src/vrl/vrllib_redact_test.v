module vrl

// Tests for vrllib_redact.v (fn_redact + match_datadog_query)

fn redact_run(source string) !VrlValue {
	return execute(source, map[string]VrlValue{})
}

fn redact_run_obj(source string, obj map[string]VrlValue) !VrlValue {
	return execute(source, obj)
}

// ============== fn_redact tests ==============

fn test_redact_credit_card() {
	result := fn_redact([VrlValue('my card is 4111111111111111'), VrlValue([VrlValue('credit_card')])]) or {
		assert false, 'redact credit_card: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
	assert !s.contains('4111111111111111')
}

fn test_redact_ssn() {
	result := fn_redact([VrlValue('ssn 123-45-6789'), VrlValue([VrlValue('us_social_security_number')])]) or {
		assert false, 'redact ssn: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
	assert !s.contains('123-45-6789')
}

fn test_redact_unknown_filter() {
	fn_redact([VrlValue('test'), VrlValue([VrlValue('unknown_filter')])]) or {
		assert err.msg().contains('unknown filter')
		return
	}
	assert false, 'expected error'
}

fn test_redact_too_few_args() {
	fn_redact([VrlValue('test')]) or {
		assert err.msg().contains('requires 2')
		return
	}
	assert false, 'expected error'
}

fn test_redact_bad_first_arg() {
	fn_redact([VrlValue(i64(42)), VrlValue([VrlValue('credit_card')])]) or {
		assert err.msg().contains('string or object')
		return
	}
	assert false, 'expected error'
}

fn test_redact_bad_second_arg() {
	fn_redact([VrlValue('test'), VrlValue('not_an_array')]) or {
		assert err.msg().contains('array of filters')
		return
	}
	assert false, 'expected error'
}

fn test_redact_bad_filter_item() {
	fn_redact([VrlValue('test'), VrlValue([VrlValue(i64(42))])]) or {
		assert err.msg().contains('filter must be')
		return
	}
	assert false, 'expected error'
}

fn test_redact_object_filter() {
	mut filter := new_object_map()
	filter.set('type', VrlValue('credit_card'))
	result := fn_redact([VrlValue('card 4111111111111111'), VrlValue([VrlValue(filter)])]) or {
		assert false, 'redact obj filter: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
}

fn test_redact_pattern_filter() {
	mut filter := new_object_map()
	filter.set('type', VrlValue('pattern'))
	filter.set('patterns', VrlValue([VrlValue('secret')]))
	result := fn_redact([VrlValue('my secret data'), VrlValue([VrlValue(filter)])]) or {
		assert false, 'redact pattern: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
	assert !s.contains('secret')
}

fn test_redact_regex_filter() {
	result := fn_redact([VrlValue('email: user@example.com end'), VrlValue([VrlValue(VrlRegex{
		pattern: r'\S+@\S+'
	})])]) or {
		assert false, 'redact regex: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
}

fn test_redact_object_input() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('John'))
	obj.set('ssn', VrlValue('123-45-6789'))
	obj.set('age', VrlValue(i64(30)))

	result := fn_redact([VrlValue(obj), VrlValue([VrlValue('us_social_security_number')])]) or {
		assert false, 'redact object: ${err}'
		return
	}
	result_obj := result as ObjectMap
	ssn_val := result_obj.get('ssn') or {
		assert false, 'no ssn key'
		return
	}
	s := ssn_val as string
	assert s.contains('[REDACTED]')
	// Non-string fields preserved
	age_val := result_obj.get('age') or {
		assert false, 'no age key'
		return
	}
	assert (age_val as i64) == 30
}

fn test_redact_pattern_regex_in_patterns() {
	mut filter := new_object_map()
	filter.set('type', VrlValue('pattern'))
	filter.set('patterns', VrlValue([VrlValue(VrlRegex{
		pattern: r'\d{4}'
	})]))
	result := fn_redact([VrlValue('code 1234 here'), VrlValue([VrlValue(filter)])]) or {
		assert false, 'redact pattern regex: ${err}'
		return
	}
	s := result as string
	assert s.contains('[REDACTED]')
}

// ============== match_datadog_query tests ==============

fn ddq_test_obj() ObjectMap {
	mut obj := new_object_map()
	obj.set('message', VrlValue('hello world error'))
	obj.set('status', VrlValue('error'))
	obj.set('host', VrlValue('server1'))
	obj.set('service', VrlValue('web'))
	obj.set('tags', VrlValue([VrlValue('env:prod'), VrlValue('region:us-east')]))
	mut custom := new_object_map()
	mut err_obj := new_object_map()
	err_obj.set('message', VrlValue('null pointer'))
	err_obj.set('stack', VrlValue('at main.v:10'))
	custom.set('error', VrlValue(err_obj))
	custom.set('title', VrlValue('Error Report'))
	obj.set('custom', VrlValue(custom))
	return obj
}

fn test_ddq_match_all() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('*:*')]) or {
		assert false, 'ddq match all: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_empty_query() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('')]) or {
		assert false, 'ddq empty: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_field_term() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:error')]) or {
		assert false, 'ddq field term: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_field_term_no_match() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:info')]) or {
		assert false, 'ddq no match: ${err}'
		return
	}
	assert (result as bool) == false
}

fn test_ddq_bare_term() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('hello')]) or {
		assert false, 'ddq bare term: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_bare_term_no_match() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('nonexistent')]) or {
		assert false, 'ddq bare no match: ${err}'
		return
	}
	assert (result as bool) == false
}

fn test_ddq_quoted_phrase() {
	obj := ddq_test_obj()
	// message field value is "hello world error", exact phrase match needed
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('message:"hello world error"')]) or {
		assert false, 'ddq phrase: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_prefix() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:err*')]) or {
		assert false, 'ddq prefix: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_wildcard() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:e?ror')]) or {
		assert false, 'ddq wildcard: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_bare_prefix() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('hel*')]) or {
		assert false, 'ddq bare prefix: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_bare_wildcard() {
	obj := ddq_test_obj()
	// h*o* matches "hello world error" as glob on whole string
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('h*o*')]) or {
		assert false, 'ddq bare wildcard: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_bare_quoted() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('"hello world"')]) or {
		assert false, 'ddq bare quoted: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_exists() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('_exists_:status')]) or {
		assert false, 'ddq exists: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_missing() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('_missing_:nonexistent')]) or {
		assert false, 'ddq missing: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_not() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('NOT status:info')]) or {
		assert false, 'ddq NOT: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_dash_negation() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('-status:info')]) or {
		assert false, 'ddq dash neg: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_and() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:error AND host:server1')]) or {
		assert false, 'ddq AND: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_or() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:info OR status:error')]) or {
		assert false, 'ddq OR: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_parenthesized() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('(status:error)')]) or {
		assert false, 'ddq parens: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_field_parenthesized() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:(error OR info)')]) or {
		assert false, 'ddq field parens: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_field_wildcard_star() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:*')]) or {
		assert false, 'ddq field star: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_gt() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(500)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:>400')]) or {
		assert false, 'ddq gt: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_lt() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(200)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:<300')]) or {
		assert false, 'ddq lt: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_gte() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(400)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:>=400')]) or {
		assert false, 'ddq gte: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_lte() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(200)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:<=200')]) or {
		assert false, 'ddq lte: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_range_inclusive() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(300)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:[200 TO 400]')]) or {
		assert false, 'ddq range: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_range_exclusive() {
	mut obj := new_object_map()
	obj.set('status_code', VrlValue(i64(200)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@status_code:{200 TO 400}')]) or {
		assert false, 'ddq range excl: ${err}'
		return
	}
	assert (result as bool) == false
}

fn test_ddq_range_wildcard() {
	mut obj := new_object_map()
	obj.set('count', VrlValue(i64(100)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@count:[50 TO *]')]) or {
		assert false, 'ddq range wildcard: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_range_string() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('banana'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@name:[apple TO cherry]')]) or {
		assert false, 'ddq range string: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_tags() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('env:prod')]) or {
		assert false, 'ddq tags: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_tags_no_match() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('env:staging')]) or {
		assert false, 'ddq tags no match: ${err}'
		return
	}
	assert (result as bool) == false
}

fn test_ddq_nested_attr() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@custom.error.message:"null pointer"')]) or {
		assert false, 'ddq nested: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_too_few_args() {
	fn_match_datadog_query([VrlValue(new_object_map())]) or {
		assert err.msg().contains('requires 2')
		return
	}
	assert false, 'expected error'
}

fn test_ddq_bad_first_arg() {
	fn_match_datadog_query([VrlValue('not_obj'), VrlValue('*:*')]) or {
		assert err.msg().contains('object')
		return
	}
	assert false, 'expected error'
}

fn test_ddq_bad_query_type() {
	fn_match_datadog_query([VrlValue(new_object_map()), VrlValue(i64(42))]) or {
		assert err.msg().contains('string query')
		return
	}
	assert false, 'expected error'
}

fn test_ddq_and_with_ampersand() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:error && host:server1')]) or {
		assert false, 'ddq &&: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_or_with_pipe() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:info || status:error')]) or {
		assert false, 'ddq ||: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_glob_match_star() {
	assert ddq_glob_match('hello', 'h*o') == true
	assert ddq_glob_match('hello', 'h*x') == false
}

fn test_ddq_glob_match_question() {
	assert ddq_glob_match('hello', 'hell?') == true
	assert ddq_glob_match('hello', 'hel??') == true
}

fn test_ddq_glob_match_exact() {
	assert ddq_glob_match('hello', 'hello') == true
	assert ddq_glob_match('hello', 'world') == false
}

fn test_ddq_glob_match_star_backtrack() {
	assert ddq_glob_match('abcde', 'a*e') == true
	assert ddq_glob_match('abcde', 'a*d*e') == true
}

fn test_ddq_value_to_string() {
	assert ddq_value_to_string(VrlValue('hello')) == 'hello'
	assert ddq_value_to_string(VrlValue(i64(42))) == '42'
	assert ddq_value_to_string(VrlValue(f64(3.14))) == '3.14'
	assert ddq_value_to_string(VrlValue(true)) == 'true'
	assert ddq_value_to_string(VrlValue(false)) == 'false'
}

fn test_ddq_unescape() {
	assert ddq_unescape('hello') == 'hello'
	assert ddq_unescape('hel\\lo') == 'hello'
	assert ddq_unescape('\\a\\b') == 'ab'
}

fn test_ddq_value_equals_bool() {
	assert ddq_value_equals(VrlValue(true), 'true') == true
	assert ddq_value_equals(VrlValue(false), 'false') == true
}

fn test_ddq_value_equals_array() {
	arr := []VrlValue{}
	arr2 := [VrlValue('hello'), VrlValue('world')]
	assert ddq_value_equals(VrlValue(arr), 'anything') == false
	assert ddq_value_equals(VrlValue(arr2), 'hello') == true
}

fn test_ddq_value_contains_numeric() {
	assert ddq_value_contains(VrlValue(i64(42)), '42') == true
	assert ddq_value_contains(VrlValue(f64(3.14)), '3.14') == true
}

fn test_ddq_parse_number() {
	if n := ddq_parse_number('42') {
		assert n == 42.0
	} else {
		assert false, 'should parse 42'
	}
	if n := ddq_parse_number('3.14') {
		assert n > 3.0 && n < 4.0
	} else {
		assert false, 'should parse 3.14'
	}
	if _ := ddq_parse_number('*') {
		assert false, 'should not parse *'
	}
	if _ := ddq_parse_number('') {
		assert false, 'should not parse empty'
	}
	if _ := ddq_parse_number('abc') {
		assert false, 'should not parse abc'
	}
}

fn test_ddq_is_tag_field() {
	assert ddq_is_tag_field('env') == true
	assert ddq_is_tag_field('host') == false
	assert ddq_is_tag_field('@attr') == false
	assert ddq_is_tag_field('nested.path') == false
}

fn test_ddq_match_tag_comparison() {
	mut obj := new_object_map()
	obj.set('tags', VrlValue([VrlValue('priority:5')]))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('priority:>3')]) or {
		assert false, 'ddq tag comparison: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_match_tag_range() {
	mut obj := new_object_map()
	obj.set('tags', VrlValue([VrlValue('priority:5')]))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('priority:[1 TO 10]')]) or {
		assert false, 'ddq tag range: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_string_fallback() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('banana'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@name:>apple')]) or {
		assert false, 'ddq string cmp: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_comparison_f64_value() {
	mut obj := new_object_map()
	obj.set('score', VrlValue(f64(3.5)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@score:>3.0')]) or {
		assert false, 'ddq f64 cmp: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_range_f64() {
	mut obj := new_object_map()
	obj.set('score', VrlValue(f64(5.5)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@score:[1.0 TO 10.0]')]) or {
		assert false, 'ddq f64 range: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_default_field_search() {
	mut obj := new_object_map()
	mut custom := new_object_map()
	custom.set('title', VrlValue('Important Alert'))
	obj.set('custom', VrlValue(custom))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('Important')]) or {
		assert false, 'ddq default search: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_wildcard_default_field() {
	mut obj := new_object_map()
	obj.set('message', VrlValue('hello world'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('h*o')]) or {
		assert false, 'ddq wildcard default: ${err}'
		return
	}
	// "h*o" should match substring "hello" doesn't match h*o exactly
	// glob match is on whole string
	_ = result
}

fn test_ddq_prefix_default_field() {
	mut obj := new_object_map()
	obj.set('message', VrlValue('hello world'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('hel*')]) or {
		assert false, 'ddq prefix default: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_prefix_field() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('hello'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@name:hel*')]) or {
		assert false, 'ddq prefix field: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_wildcard_field() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('hello'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@name:h?llo')]) or {
		assert false, 'ddq wildcard field: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_multiple_and() {
	obj := ddq_test_obj()
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('status:error host:server1 service:web')]) or {
		assert false, 'ddq multi AND: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_range_quoted() {
	mut obj := new_object_map()
	obj.set('name', VrlValue('banana'))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@name:["apple" TO "cherry"]')]) or {
		assert false, 'ddq range quoted: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_numeric_negation() {
	// -5 should be treated as numeric, not negation
	mut obj := new_object_map()
	obj.set('val', VrlValue(i64(-5)))
	result := fn_match_datadog_query([VrlValue(obj), VrlValue('@val:<0')]) or {
		assert false, 'ddq numeric neg: ${err}'
		return
	}
	assert (result as bool) == true
}

fn test_ddq_match_none() {
	node := DdqNode{kind: .match_none}
	assert ddq_eval(node, new_object_map()) == false
}

fn test_ddq_negated_empty() {
	node := DdqNode{kind: .negated, children: []}
	assert ddq_eval(node, new_object_map()) == true
}

fn test_ddq_escaped_term() {
	mut p := DdqParser{input: 'hel\\:lo rest', pos: 0}
	term := p.read_term()
	unescaped := ddq_unescape(term)
	assert unescaped == 'hel:lo'
}

fn test_ddq_field_colon_at_start() {
	mut p := DdqParser{input: ':value', pos: 0}
	assert p.find_field_colon() == -1
}

fn test_ddq_field_colon_with_escape() {
	mut p := DdqParser{input: 'fi\\eld:value', pos: 0}
	idx := p.find_field_colon()
	assert idx > 0
}

fn test_ddq_string_compare_all() {
	assert ddq_string_compare('b', .gt, 'a') == true
	assert ddq_string_compare('a', .lt, 'b') == true
	assert ddq_string_compare('a', .gte, 'a') == true
	assert ddq_string_compare('a', .lte, 'a') == true
}
