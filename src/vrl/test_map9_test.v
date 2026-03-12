module vrl

import os

fn test_map_complex_exact_conformance() {
	path := os.join_path(os.dir(os.dir(os.dir(@FILE))), 'upstream', 'vrl', 'lib', 'tests', 'tests', 'rfcs', '8381', 'map_complex_dynamic_object_based_on_conditionals.vrl')
	content := os.read_file(path) or {
		assert false, 'cannot read'
		return
	}
	lines := content.split_into_lines()

	// Exact replication of parse_test_file logic
	mut obj_json := ''
	mut res_lines := []string{}
	mut in_res := false
	mut in_obj := false
	mut src_lines := []string{}
	mut done := false

	for line in lines {
		tr := line.trim_space()
		if !done && tr.starts_with('#') {
			c := tr[1..].trim_space()
			if c.starts_with('SKIP') || c == 'skip' { continue }
			if c.starts_with('DIAGNOSTICS') { continue }
			if c.starts_with('object:') {
				in_res = false
				in_obj = true
				op := c['object:'.len..].trim_space()
				if op.len > 0 {
					obj_json = op
					if is_json_balanced(obj_json) {
						in_obj = false
					}
				}
				continue
			}
			if c.starts_with('result:') {
				in_obj = false
				in_res = true
				rp := c['result:'.len..].trim_space()
				if rp.len > 0 {
					res_lines << rp
				}
				continue
			}
			if in_res {
				res_lines << c
				continue
			}
			if in_obj {
				obj_json += ' ' + c
				if is_json_balanced(obj_json) {
					in_obj = false
				}
				continue
			}
			continue
		}
		done = true
		in_res = false
		in_obj = false
		src_lines << line
	}

	src := src_lines.join('\n').trim_right('\n')
	oj := obj_json.trim_space()

	// Parse object
	ov := parse_json_recursive(oj) or {
		assert false, 'parse obj failed: ${err}\nobj_json first 80: ${oj[..if oj.len > 80 { 80 } else { oj.len }]}'
		return
	}
	o := ov
	obj := match o {
		ObjectMap { o.to_map() }
		else {
			assert false, 'not ObjectMap'
			return
		}
	}

	// Check object has input key
	assert 'input' in obj, 'obj missing input key. Keys: ${obj.keys()}'

	actual := execute(src, obj) or {
		assert false, 'execute failed: ${err}\nsrc first 200: ${src[..if src.len > 200 { 200 } else { src.len }]}'
		return
	}
	actual_json := vrl_to_json(actual)
	expected := '{"input":[{"items":[{"userAttributes":[{"Name":"Peter"},{"__type":"String","key":"Address","values":[{"country":"Japan"}]}],"userId":[{"uId":"0000001"},{"uId":"0000002"}]}]}]}'
	assert actual_json == expected, 'got: ${actual_json}\nsrc lines count: ${src_lines.len}'
}
