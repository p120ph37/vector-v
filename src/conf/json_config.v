module conf

import json as j

// parse_json_config parses a JSON configuration string into a PipelineConfig.
// Supports the same structure as TOML/YAML but in JSON format:
//
//   {
//     "sources": {
//       "my_source": { "type": "stdin" }
//     },
//     "transforms": {
//       "my_transform": {
//         "type": "remap",
//         "inputs": ["my_source"],
//         "source": ".env = \"prod\""
//       }
//     },
//     "sinks": {
//       "my_sink": {
//         "type": "console",
//         "inputs": ["my_transform"],
//         "encoding.codec": "json"
//       }
//     }
//   }
pub fn parse_json_config(content string) !PipelineConfig {
	mut pipeline := PipelineConfig{}

	// Parse the raw JSON using V's json decode into a generic map
	raw := j.decode(JsonConfig, content) or {
		return error('invalid JSON config: ${err}')
	}

	// Process sources
	for id, comp in raw.sources {
		pipeline.sources[id] = json_to_component(comp)
	}

	// Process transforms
	for id, comp in raw.transforms {
		pipeline.transforms[id] = json_to_component(comp)
	}

	// Process sinks
	for id, comp in raw.sinks {
		pipeline.sinks[id] = json_to_component(comp)
	}

	if pipeline.sources.len == 0 {
		return error('config must contain at least one source')
	}
	if pipeline.sinks.len == 0 {
		return error('config must contain at least one sink')
	}

	return pipeline
}

// JsonConfig is the top-level JSON config structure.
struct JsonConfig {
	sources    map[string]JsonComponent
	transforms map[string]JsonComponent
	sinks      map[string]JsonComponent
}

// JsonComponent represents a single component in JSON config.
struct JsonComponent {
	typ     string   @[json: 'type']
	inputs  []string
	options map[string]string @[json: 'options']
	// All other fields are captured as flat key-value pairs
	source              string
	address             string
	mode                string
	interval            string
	format              string
	count               string
	endpoint            string
	path                string
	rate                string
	key_field           string
	exclude             string
	token               string
	encoding_codec      string @[json: 'encoding.codec']
	container_name      string
	storage_account     string
	project_id          string
	log_id              string
	stream_name         string
	topic               string
	batch_max_events    string @[json: 'batch.max_events']
	batch_timeout_secs  string @[json: 'batch.timeout_secs']
	batch_timeout_ms    string @[json: 'batch.timeout_ms']
}

fn json_to_component(jc JsonComponent) ComponentConfig {
	mut comp := ComponentConfig{
		typ: jc.typ
		inputs: jc.inputs
	}

	// Copy explicit options
	for k, v in jc.options {
		comp.options[k] = v
	}

	// Copy well-known fields if set
	if jc.source.len > 0 { comp.options['source'] = jc.source }
	if jc.address.len > 0 { comp.options['address'] = jc.address }
	if jc.mode.len > 0 { comp.options['mode'] = jc.mode }
	if jc.interval.len > 0 { comp.options['interval'] = jc.interval }
	if jc.format.len > 0 { comp.options['format'] = jc.format }
	if jc.count.len > 0 { comp.options['count'] = jc.count }
	if jc.endpoint.len > 0 { comp.options['endpoint'] = jc.endpoint }
	if jc.path.len > 0 { comp.options['path'] = jc.path }
	if jc.rate.len > 0 { comp.options['rate'] = jc.rate }
	if jc.key_field.len > 0 { comp.options['key_field'] = jc.key_field }
	if jc.exclude.len > 0 { comp.options['exclude'] = jc.exclude }
	if jc.token.len > 0 { comp.options['token'] = jc.token }
	if jc.encoding_codec.len > 0 { comp.options['encoding.codec'] = jc.encoding_codec }
	if jc.container_name.len > 0 { comp.options['container_name'] = jc.container_name }
	if jc.storage_account.len > 0 { comp.options['storage_account'] = jc.storage_account }
	if jc.project_id.len > 0 { comp.options['project_id'] = jc.project_id }
	if jc.log_id.len > 0 { comp.options['log_id'] = jc.log_id }
	if jc.stream_name.len > 0 { comp.options['stream_name'] = jc.stream_name }
	if jc.topic.len > 0 { comp.options['topic'] = jc.topic }
	if jc.batch_max_events.len > 0 { comp.options['batch.max_events'] = jc.batch_max_events }
	if jc.batch_timeout_secs.len > 0 { comp.options['batch.timeout_secs'] = jc.batch_timeout_secs }
	if jc.batch_timeout_ms.len > 0 { comp.options['batch.timeout_ms'] = jc.batch_timeout_ms }

	return comp
}
