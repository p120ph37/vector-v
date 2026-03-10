module conf

fn test_parse_simple_config() {
	content := '
[sources.in]
type = "stdin"

[sinks.out]
type = "console"
inputs = ["in"]
encoding.codec = "json"
'
	cfg := parse_toml_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.sinks.len == 1
	assert cfg.sources['in'].typ == 'stdin'
	assert cfg.sinks['out'].typ == 'console'
	assert cfg.sinks['out'].inputs == ['in']
}

fn test_parse_config_with_transform() {
	content := '
[sources.in]
type = "stdin"

[transforms.parse]
type = "remap"
inputs = ["in"]
source = ".env = \\"prod\\""

[sinks.out]
type = "console"
inputs = ["parse"]
encoding.codec = "json"
'
	cfg := parse_toml_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.transforms.len == 1
	assert cfg.sinks.len == 1
	assert cfg.transforms['parse'].typ == 'remap'
	assert cfg.transforms['parse'].inputs == ['in']
}

fn test_config_no_sources_errors() {
	content := '
[sinks.out]
type = "console"
inputs = ["in"]
'
	if _ := parse_toml_config(content) {
		assert false, 'expected error for missing sources'
	}
}

fn test_config_no_sinks_errors() {
	content := '
[sources.in]
type = "stdin"
'
	if _ := parse_toml_config(content) {
		assert false, 'expected error for missing sinks'
	}
}

fn test_validate_topology_ok() {
	content := '
[sources.in]
type = "stdin"

[sinks.out]
type = "console"
inputs = ["in"]
'
	cfg := parse_toml_config(content) or { panic(err) }
	cfg.validate_topology() or { panic(err) }
}

fn test_validate_topology_bad_input() {
	mut cfg := PipelineConfig{}
	cfg.sources['in'] = ComponentConfig{
		typ: 'stdin'
	}
	cfg.sinks['out'] = ComponentConfig{
		typ: 'console'
		inputs: ['nonexistent']
	}
	if _ := cfg.validate_topology() {
		assert false, 'expected error for bad input reference'
	}
}

fn test_validate_topology_no_sink_inputs() {
	mut cfg := PipelineConfig{}
	cfg.sources['in'] = ComponentConfig{
		typ: 'stdin'
	}
	cfg.sinks['out'] = ComponentConfig{
		typ: 'console'
		inputs: []
	}
	if _ := cfg.validate_topology() {
		assert false, 'expected error for empty sink inputs'
	}
}

fn test_unquote_double() {
	assert unquote('"hello"') == 'hello'
}

fn test_unquote_single() {
	assert unquote("'hello'") == 'hello'
}

fn test_unquote_no_quotes() {
	assert unquote('hello') == 'hello'
}

fn test_unquote_escaped() {
	assert unquote('"say \\"hi\\""') == 'say "hi"'
}

fn test_parse_string_array() {
	result := parse_string_array('["a", "b", "c"]')
	assert result == ['a', 'b', 'c']
}

fn test_parse_string_array_single() {
	result := parse_string_array('"single"')
	assert result == ['single']
}
