module conf

fn test_parse_json_simple() {
	content := '{
		"sources": {
			"in": { "type": "stdin" }
		},
		"sinks": {
			"out": {
				"type": "console",
				"inputs": ["in"],
				"encoding.codec": "json"
			}
		}
	}'
	cfg := parse_json_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.sinks.len == 1
	assert cfg.sources['in'].typ == 'stdin'
	assert cfg.sinks['out'].typ == 'console'
	assert cfg.sinks['out'].inputs == ['in']
}

fn test_parse_json_with_transform() {
	content := '{
		"sources": {
			"in": { "type": "stdin" }
		},
		"transforms": {
			"parse": {
				"type": "remap",
				"inputs": ["in"],
				"source": ".env = \\"prod\\""
			}
		},
		"sinks": {
			"out": {
				"type": "console",
				"inputs": ["parse"]
			}
		}
	}'
	cfg := parse_json_config(content) or { panic(err) }
	assert cfg.sources.len == 1
	assert cfg.transforms.len == 1
	assert cfg.sinks.len == 1
	assert cfg.transforms['parse'].typ == 'remap'
	assert cfg.transforms['parse'].inputs == ['in']
}

fn test_parse_json_no_sources() {
	content := '{
		"sinks": {
			"out": { "type": "console", "inputs": ["in"] }
		}
	}'
	if _ := parse_json_config(content) {
		assert false, 'expected error for missing sources'
	}
}

fn test_parse_json_no_sinks() {
	content := '{
		"sources": {
			"in": { "type": "stdin" }
		}
	}'
	if _ := parse_json_config(content) {
		assert false, 'expected error for missing sinks'
	}
}

fn test_parse_json_invalid_json() {
	if _ := parse_json_config('not json') {
		assert false, 'expected error for invalid JSON'
	}
}

fn test_parse_json_multiple_inputs() {
	content := '{
		"sources": {
			"src1": { "type": "stdin" },
			"src2": { "type": "demo_logs" }
		},
		"sinks": {
			"out": {
				"type": "console",
				"inputs": ["src1", "src2"]
			}
		}
	}'
	cfg := parse_json_config(content) or { panic(err) }
	assert cfg.sources.len == 2
	assert cfg.sinks['out'].inputs.len == 2
}

fn test_parse_json_with_options() {
	content := '{
		"sources": {
			"in": {
				"type": "http_client",
				"endpoint": "http://example.com",
				"interval": "30"
			}
		},
		"sinks": {
			"out": {
				"type": "console",
				"inputs": ["in"]
			}
		}
	}'
	cfg := parse_json_config(content) or { panic(err) }
	assert cfg.sources['in'].typ == 'http_client'
	assert cfg.sources['in'].options['endpoint'] == 'http://example.com'
	assert cfg.sources['in'].options['interval'] == '30'
}
