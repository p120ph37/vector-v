module conf

// parse_config auto-detects the format (TOML, YAML, JSON) and parses accordingly.
// Detection is based on file extension passed in `path`, or content heuristics.
pub fn parse_config(content string, path string) !PipelineConfig {
	fmt := detect_format(content, path)
	match fmt {
		.toml { return parse_toml_config(content) }
		.yaml { return parse_yaml_config(content) }
		.json { return parse_json_config(content) }
	}
}

enum ConfigFormat {
	toml
	yaml
	json
}

fn detect_format(content string, path string) ConfigFormat {
	// Check file extension first
	lower_path := path.to_lower()
	if lower_path.ends_with('.yaml') || lower_path.ends_with('.yml') {
		return .yaml
	}
	if lower_path.ends_with('.json') {
		return .json
	}
	if lower_path.ends_with('.toml') {
		return .toml
	}

	// Content-based heuristics
	trimmed := content.trim_space()
	if trimmed.starts_with('{') {
		return .json
	}

	// YAML typically uses "key:" at the start; TOML uses "[section]"
	// Check if the first non-comment line looks like YAML or TOML
	for line in content.split_into_lines() {
		stripped := line.trim_space()
		if stripped.len == 0 || stripped.starts_with('#') {
			continue
		}
		if stripped.starts_with('[') {
			return .toml
		}
		// YAML: top-level keys like "sources:", "transforms:", "sinks:"
		if stripped == 'sources:' || stripped == 'transforms:' || stripped == 'sinks:' {
			return .yaml
		}
		break
	}

	// Default to TOML for backwards compatibility
	return .toml
}
