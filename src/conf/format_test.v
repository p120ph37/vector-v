module conf

fn test_detect_format_toml_ext() {
	assert detect_format('', 'config.toml') == .toml
	assert detect_format('', 'path/to/config.TOML') == .toml
}

fn test_detect_format_yaml_ext() {
	assert detect_format('', 'config.yaml') == .yaml
	assert detect_format('', 'config.yml') == .yaml
	assert detect_format('', 'path/to/config.YAML') == .yaml
}

fn test_detect_format_json_ext() {
	assert detect_format('', 'config.json') == .json
	assert detect_format('', 'config.JSON') == .json
}

fn test_detect_format_json_content() {
	assert detect_format('{ "sources": {} }', 'config') == .json
	assert detect_format('  { "sources": {} }', 'config') == .json
}

fn test_detect_format_yaml_content() {
	assert detect_format('sources:\n  in:\n    type: stdin', 'config') == .yaml
}

fn test_detect_format_toml_content() {
	assert detect_format('[sources.in]\ntype = "stdin"', 'config') == .toml
}

fn test_detect_format_default_toml() {
	assert detect_format('something = "value"', 'config') == .toml
}

fn test_parse_config_toml() {
	content := '
[sources.in]
type = "stdin"

[sinks.out]
type = "console"
inputs = ["in"]
'
	cfg := parse_config(content, 'config.toml') or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
}

fn test_parse_config_yaml() {
	content := '
sources:
  in:
    type: stdin

sinks:
  out:
    type: console
    inputs: [in]
'
	cfg := parse_config(content, 'config.yaml') or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
}

fn test_parse_config_json() {
	content := '{
		"sources": { "in": { "type": "stdin" } },
		"sinks": { "out": { "type": "console", "inputs": ["in"] } }
	}'
	cfg := parse_config(content, 'config.json') or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
}

fn test_parse_config_autodetect_json() {
	content := '{ "sources": { "in": { "type": "stdin" } }, "sinks": { "out": { "type": "console", "inputs": ["in"] } } }'
	cfg := parse_config(content, 'myconfig') or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
}

fn test_parse_config_autodetect_yaml() {
	content := 'sources:
  in:
    type: stdin

sinks:
  out:
    type: console
    inputs: [in]
'
	cfg := parse_config(content, 'myconfig') or { panic(err) }
	assert cfg.sources['in'].typ == 'stdin'
}
