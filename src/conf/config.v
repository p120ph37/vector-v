module conf

// ComponentKind represents the type of component in the pipeline.
pub enum ComponentKind {
	source
	transform
	sink
}

// ComponentConfig holds the configuration for a single component.
pub struct ComponentConfig {
pub mut:
	typ     string
	inputs  []string
	options map[string]string
}

// PipelineConfig holds the parsed configuration for a Vector-V pipeline.
pub struct PipelineConfig {
pub mut:
	sources    map[string]ComponentConfig
	transforms map[string]ComponentConfig
	sinks      map[string]ComponentConfig
}

// parse_toml_config parses a TOML configuration string into a PipelineConfig.
pub fn parse_toml_config(content string) !PipelineConfig {
	mut pipeline := PipelineConfig{}
	lines := content.split_into_lines()
	mut current_kind := ComponentKind.source
	mut current_id := ''
	mut current_comp := ComponentConfig{}
	mut in_component := false

	for line in lines {
		trimmed := line.trim_space()

		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}

		if trimmed.starts_with('[') && trimmed.ends_with(']') {
			if in_component {
				save_component(mut pipeline, current_kind, current_id, current_comp)
			}

			section := trimmed[1..trimmed.len - 1]
			parts := section.split('.')
			if parts.len >= 2 {
				kind_str := parts[0]
				current_id = parts[1..].join('.')
				current_kind = match kind_str {
					'sources' { ComponentKind.source }
					'transforms' { ComponentKind.transform }
					'sinks' { ComponentKind.sink }
					else { ComponentKind.source }
				}
				current_comp = ComponentConfig{}
				in_component = true
			}
			continue
		}

		if in_component {
			eq_pos := trimmed.index_u8(`=`)
			if eq_pos > 0 {
				key := trimmed[..eq_pos].trim_space()
				raw_val := trimmed[eq_pos + 1..].trim_space()
				val := unquote(raw_val)

				if key == 'type' {
					current_comp.typ = val
				} else if key == 'inputs' {
					current_comp.inputs = parse_string_array(raw_val)
				} else {
					current_comp.options[key] = val
				}
			}
		}
	}

	if in_component {
		save_component(mut pipeline, current_kind, current_id, current_comp)
	}

	if pipeline.sources.len == 0 {
		return error('config must contain at least one source')
	}
	if pipeline.sinks.len == 0 {
		return error('config must contain at least one sink')
	}

	return pipeline
}

fn save_component(mut pipeline PipelineConfig, kind ComponentKind, id string, comp ComponentConfig) {
	match kind {
		.source { pipeline.sources[id] = comp }
		.transform { pipeline.transforms[id] = comp }
		.sink { pipeline.sinks[id] = comp }
	}
}

fn unquote(s string) string {
	if s.len >= 2 {
		if (s[0] == `"` && s[s.len - 1] == `"`) || (s[0] == `'` && s[s.len - 1] == `'`) {
			inner := s[1..s.len - 1]
			// Handle escaped quotes
			return inner.replace('\\"', '"').replace("\\'", "'").replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
		}
	}
	return s
}

fn parse_string_array(s string) []string {
	trimmed := s.trim_space()
	if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
		return [unquote(trimmed)]
	}
	inner := trimmed[1..trimmed.len - 1]
	parts := inner.split(',')
	mut result := []string{}
	for part in parts {
		val := unquote(part.trim_space())
		if val.len > 0 {
			result << val
		}
	}
	return result
}

// validate_topology checks that all input references point to existing components.
pub fn (pipeline &PipelineConfig) validate_topology() ! {
	mut all_ids := map[string]bool{}
	for id, _ in pipeline.sources {
		all_ids[id] = true
	}
	for id, _ in pipeline.transforms {
		all_ids[id] = true
	}

	for id, comp in pipeline.transforms {
		for input in comp.inputs {
			if input !in all_ids {
				return error('transform "${id}" references unknown input "${input}"')
			}
		}
		all_ids[id] = true
	}

	for id, comp in pipeline.sinks {
		if comp.inputs.len == 0 {
			return error('sink "${id}" has no inputs')
		}
		for input in comp.inputs {
			if input !in all_ids {
				return error('sink "${id}" references unknown input "${input}"')
			}
		}
	}
}
