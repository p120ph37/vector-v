module vrl

fn ddq_obj(pairs ...string) ObjectMap {
	mut m := new_object_map()
	mut i := 0
	for i + 1 < pairs.len {
		m.set(pairs[i], VrlValue(pairs[i + 1]))
		i += 2
	}
	return m
}

fn ddq_test(obj ObjectMap, query string, expected bool) {
	result := fn_match_datadog_query([VrlValue(obj), VrlValue(query)]) or {
		panic('match_datadog_query error for query "${query}": ${err.msg()}')
	}
	r := result as bool
	assert r == expected, 'query "${query}" expected=${expected} actual=${r}'
}

fn test_ddq_match_all() {
	ddq_test(ddq_obj('a', 'b'), '*:*', true)
}

fn test_ddq_empty_query() {
	ddq_test(ddq_obj('a', 'b'), '', true)
}

fn test_ddq_attr_field_exact() {
	obj := ddq_obj('name', 'foobar')
	ddq_test(obj, '@name:foobar', true)
	ddq_test(obj, '@name:other', false)
}

fn test_ddq_attr_prefix() {
	obj := ddq_obj('name', 'foobar')
	ddq_test(obj, '@name:foo*', true)
	ddq_test(obj, '@name:baz*', false)
}

fn test_ddq_attr_wildcard() {
	obj := ddq_obj('name', 'foobar')
	ddq_test(obj, '@name:f*r', true)
	ddq_test(obj, '@name:f?obar', true)
	ddq_test(obj, '@name:x*r', false)
}

fn test_ddq_default_field_contains() {
	obj := ddq_obj('message', 'contains this and that')
	ddq_test(obj, 'this', true)
	ddq_test(obj, 'that', true)
	ddq_test(obj, 'missing', false)
}

fn test_ddq_or_query() {
	obj := ddq_obj('message', 'contains this and that')
	ddq_test(obj, 'this OR that', true)
	ddq_test(obj, 'this OR missing', true)
	ddq_test(obj, 'missing OR absent', false)
}

fn test_ddq_and_query() {
	obj := ddq_obj('message', 'contains this and that')
	ddq_test(obj, 'this AND that', true)
	ddq_test(obj, 'this AND missing', false)
}

fn test_ddq_not_query() {
	obj := ddq_obj('message', 'hello world')
	ddq_test(obj, 'NOT missing', true)
	ddq_test(obj, 'NOT hello', false)
	ddq_test(obj, '-hello', false)
}

fn test_ddq_exists() {
	obj := ddq_obj('name', 'test')
	ddq_test(obj, '_exists_:name', true)
	ddq_test(obj, '_exists_:missing', false)
}

fn test_ddq_missing() {
	obj := ddq_obj('name', 'test')
	ddq_test(obj, '_missing_:absent', true)
	ddq_test(obj, '_missing_:name', false)
}

fn test_ddq_comparison_numeric() {
	mut obj := new_object_map()
	obj.set('status', VrlValue(i64(500)))
	ddq_test(obj, '@status:>400', true)
	ddq_test(obj, '@status:<400', false)
	ddq_test(obj, '@status:>=500', true)
	ddq_test(obj, '@status:<=499', false)
}

fn test_ddq_range_numeric() {
	mut obj := new_object_map()
	obj.set('code', VrlValue(i64(404)))
	ddq_test(obj, '@code:[400 TO 500]', true)
	ddq_test(obj, '@code:[405 TO 500]', false)
	ddq_test(obj, '@code:{403 TO 405}', true)
}

fn test_ddq_range_string() {
	obj := ddq_obj('level', 'info')
	ddq_test(obj, '@level:[error TO warning]', true)
	ddq_test(obj, '@level:[a TO z]', true)
}

fn test_ddq_quoted_phrase() {
	obj := ddq_obj('message', 'exact phrase here')
	ddq_test(obj, '"exact phrase"', true)
	ddq_test(obj, '"wrong phrase"', false)
}

fn test_ddq_tag_search() {
	mut obj := new_object_map()
	mut tags := []VrlValue{}
	tags << VrlValue('env:production')
	tags << VrlValue('region:us-east')
	obj.set('tags', VrlValue(tags))
	ddq_test(obj, 'env:production', true)
	ddq_test(obj, 'env:staging', false)
	ddq_test(obj, 'region:us-east', true)
}

fn test_ddq_tag_range() {
	mut obj := new_object_map()
	mut tags := []VrlValue{}
	tags << VrlValue('a:x')
	tags << VrlValue('b:y')
	tags << VrlValue('c:z')
	obj.set('tags', VrlValue(tags))
	ddq_test(obj, 'b:["x" TO "z"]', true)
	ddq_test(obj, 'a:[* TO "z"]', true)
}

fn test_ddq_nested_attr() {
	mut inner := new_object_map()
	inner.set('code', VrlValue(i64(200)))
	mut obj := new_object_map()
	obj.set('http', VrlValue(inner))
	ddq_test(obj, '@http.code:200', true)
	ddq_test(obj, '@http.code:404', false)
}

fn test_ddq_parenthesized() {
	obj := ddq_obj('message', 'hello world')
	ddq_test(obj, '(hello)', true)
	ddq_test(obj, '(hello AND world)', true)
	ddq_test(obj, '(missing OR hello)', true)
}

fn test_ddq_negated_match_all() {
	ddq_test(ddq_obj('a', 'b'), '-*:*', false)
}

fn test_ddq_case_insensitive() {
	obj := ddq_obj('name', 'FooBar')
	ddq_test(obj, '@name:foobar', true)
	ddq_test(obj, '@name:FOOBAR', true)
}

fn test_ddq_error_non_object() {
	_ := fn_match_datadog_query([VrlValue('not an object'), VrlValue('query')]) or {
		assert err.msg().contains('object')
		return
	}
	panic('expected error for non-object')
}

fn test_ddq_error_non_string_query() {
	obj := new_object_map()
	_ := fn_match_datadog_query([VrlValue(obj), VrlValue(i64(42))]) or {
		assert err.msg().contains('string')
		return
	}
	panic('expected error for non-string query')
}
