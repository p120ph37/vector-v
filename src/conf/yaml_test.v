module conf

fn test_parse_yaml_simple() {
	content := '
sources:
  in:
    type: stdin

sinks:
  out:
    type: console
    inputs: [in]
    encoding.codec: json
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.sinks.len == 1
	assert cfg.sources['in'].typ == 'stdin'
	assert cfg.sinks['out'].typ == 'console'
	assert cfg.sinks['out'].inputs == ['in']
	assert cfg.sinks['out'].options['encoding.codec'] == 'json'
}

fn test_parse_yaml_with_transform() {
	content := '
sources:
  in:
    type: stdin

transforms:
  parse:
    type: remap
    inputs:
      - in
    source: ".env = \\"prod\\""

sinks:
  out:
    type: console
    inputs:
      - parse
    encoding.codec: json
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.transforms.len == 1
	assert cfg.sinks.len == 1
	assert cfg.transforms['parse'].typ == 'remap'
	assert cfg.transforms['parse'].inputs == ['in']
}

fn test_parse_yaml_no_sources() {
	content := '
sinks:
  out:
    type: console
    inputs: [in]
'
	if _ := parse_yaml_config(content) {
		assert false, 'expected error for missing sources'
	}
}

fn test_parse_yaml_no_sinks() {
	content := '
sources:
  in:
    type: stdin
'
	if _ := parse_yaml_config(content) {
		assert false, 'expected error for missing sinks'
	}
}

fn test_parse_yaml_inline_array() {
	content := '
sources:
  in:
    type: stdin

sinks:
  out:
    type: console
    inputs: [in]
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sinks['out'].inputs == ['in']
}

fn test_parse_yaml_multiline_inputs() {
	content := '
sources:
  src1:
    type: stdin
  src2:
    type: demo_logs

sinks:
  out:
    type: console
    inputs:
      - src1
      - src2
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sinks['out'].inputs.len == 2
	assert cfg.sinks['out'].inputs[0] == 'src1'
	assert cfg.sinks['out'].inputs[1] == 'src2'
}

fn test_parse_yaml_quoted_values() {
	content := '
sources:
  in:
    type: "stdin"

sinks:
  out:
    type: "console"
    inputs: ["in"]
    encoding.codec: "json"
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
	assert cfg.sinks['out'].typ == 'console'
	assert cfg.sinks['out'].options['encoding.codec'] == 'json'
}

fn test_parse_yaml_with_comments() {
	content := '
# This is a comment
sources:
  in:
    type: stdin  # inline comment handled by yaml parser

sinks:
  out:
    type: console
    inputs: [in]
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.sinks.len == 1
}

fn test_parse_yaml_multiple_components() {
	content := '
sources:
  web:
    type: http_client
    endpoint: http://example.com
  app:
    type: stdin

transforms:
  filter:
    type: filter
    inputs:
      - web
      - app
    condition: ".level == \\"error\\""

sinks:
  out:
    type: console
    inputs:
      - filter
'
	cfg := parse_yaml_config(content) or { panic(err) }
	assert cfg.sources.len == 2
	assert cfg.transforms.len == 1
	assert cfg.sinks.len == 1
	assert cfg.sources['web'].typ == 'http_client'
	assert cfg.sources['web'].options['endpoint'] == 'http://example.com'
}

fn test_yaml_unquote() {
	assert yaml_unquote('"hello"') == 'hello'
	assert yaml_unquote("'hello'") == 'hello'
	assert yaml_unquote('hello') == 'hello'
	assert yaml_unquote('') == ''
}

fn test_count_indent() {
	assert count_indent('hello') == 0
	assert count_indent('  hello') == 2
	assert count_indent('    hello') == 4
	assert count_indent('\thello') == 2
}

fn test_parse_yaml_inline_array_fn() {
	assert parse_yaml_inline_array('[a, b, c]') == ['a', 'b', 'c']
	assert parse_yaml_inline_array('["x", "y"]') == ['x', 'y']
	assert parse_yaml_inline_array('single') == ['single']
}
