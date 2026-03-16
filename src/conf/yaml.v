module conf

// parse_yaml_config parses a YAML configuration string into a PipelineConfig.
// Supports the same structure as TOML but in YAML format:
//
//   sources:
//     my_source:
//       type: stdin
//   transforms:
//     my_transform:
//       type: remap
//       inputs:
//         - my_source
//       source: '.env = "prod"'
//   sinks:
//     my_sink:
//       type: console
//       inputs:
//         - my_transform
//       encoding.codec: json
pub fn parse_yaml_config(content string) !PipelineConfig {
	mut pipeline := PipelineConfig{}
	lines := content.split_into_lines()

	// State tracking
	mut current_section := '' // "sources", "transforms", "sinks"
	mut current_id := ''
	mut current_comp := ComponentConfig{}
	mut in_component := false
	mut in_inputs := false
	mut base_indent := 0

	for line in lines {
		// Skip empty lines and comments
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}

		indent := count_indent(line)

		// Top-level section (indent 0)
		if indent == 0 && (trimmed == 'sources:' || trimmed == 'transforms:' || trimmed == 'sinks:') {
			if in_component && current_id.len > 0 {
				save_yaml_component(mut pipeline, current_section, current_id, current_comp)
				in_component = false
			}
			current_section = trimmed.trim_right(':')
			in_inputs = false
			continue
		}

		// Component ID level (indent 2 typically)
		if current_section.len > 0 && indent > 0 && (!in_component || indent <= base_indent) && trimmed.ends_with(':') && !trimmed.contains(' ') {
			if in_component && current_id.len > 0 {
				save_yaml_component(mut pipeline, current_section, current_id, current_comp)
			}
			current_id = trimmed.trim_right(':')
			current_comp = ComponentConfig{}
			in_component = true
			in_inputs = false
			base_indent = indent
			continue
		}

		// Inside a component
		if in_component && indent > base_indent {
			// Check if we're collecting inputs array items
			if in_inputs && trimmed.starts_with('- ') {
				val := trimmed[2..].trim_space()
				current_comp.inputs << yaml_unquote(val)
				continue
			}
			in_inputs = false

			// Key-value pair
			colon_pos := trimmed.index(':') or { continue }
			if colon_pos > 0 {
				key := trimmed[..colon_pos].trim_space()
				rest := trimmed[colon_pos + 1..].trim_space()

				if key == 'type' {
					current_comp.typ = yaml_unquote(rest)
				} else if key == 'inputs' {
					if rest.len == 0 {
						// Multi-line array follows
						in_inputs = true
					} else if rest.starts_with('[') {
						// Inline array: [a, b, c]
						current_comp.inputs = parse_yaml_inline_array(rest)
					} else {
						current_comp.inputs = [yaml_unquote(rest)]
					}
				} else {
					if rest.len > 0 {
						current_comp.options[key] = yaml_unquote(rest)
					}
				}
			}
		}
	}

	if in_component && current_id.len > 0 {
		save_yaml_component(mut pipeline, current_section, current_id, current_comp)
	}

	if pipeline.sources.len == 0 {
		return error('config must contain at least one source')
	}
	if pipeline.sinks.len == 0 {
		return error('config must contain at least one sink')
	}

	return pipeline
}

fn save_yaml_component(mut pipeline PipelineConfig, section string, id string, comp ComponentConfig) {
	match section {
		'sources' { pipeline.sources[id] = comp }
		'transforms' { pipeline.transforms[id] = comp }
		'sinks' { pipeline.sinks[id] = comp }
		else {}
	}
}

fn count_indent(line string) int {
	mut n := 0
	for c in line.bytes() {
		if c == ` ` {
			n++
		} else if c == `\t` {
			n += 2
		} else {
			break
		}
	}
	return n
}

fn yaml_unquote(s string) string {
	if s.len >= 2 {
		if (s[0] == `"` && s[s.len - 1] == `"`) || (s[0] == `'` && s[s.len - 1] == `'`) {
			return s[1..s.len - 1]
		}
	}
	return s
}

fn parse_yaml_inline_array(s string) []string {
	trimmed := s.trim_space()
	if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
		return [yaml_unquote(trimmed)]
	}
	inner := trimmed[1..trimmed.len - 1]
	parts := inner.split(',')
	mut result := []string{}
	for part in parts {
		val := yaml_unquote(part.trim_space())
		if val.len > 0 {
			result << val
		}
	}
	return result
}
