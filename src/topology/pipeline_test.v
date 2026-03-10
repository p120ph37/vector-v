module topology

import conf

fn test_resolve_transform_order_empty() {
	c := conf.PipelineConfig{
		sources: map[string]conf.ComponentConfig{}
		transforms: map[string]conf.ComponentConfig{}
		sinks: map[string]conf.ComponentConfig{}
	}
	order := resolve_transform_order(c) or { panic(err) }
	assert order.len == 0
}

fn test_resolve_transform_order_single() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src1'] = conf.ComponentConfig{
		typ: 'stdin'
		inputs: []
	}

	mut transforms_map := map[string]conf.ComponentConfig{}
	transforms_map['t1'] = conf.ComponentConfig{
		typ: 'remap'
		inputs: ['src1']
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: transforms_map
		sinks: map[string]conf.ComponentConfig{}
	}
	order := resolve_transform_order(c) or { panic(err) }
	assert order.len == 1
	assert order[0] == 't1'
}

fn test_resolve_transform_order_chain() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src1'] = conf.ComponentConfig{
		typ: 'stdin'
		inputs: []
	}

	mut transforms_map := map[string]conf.ComponentConfig{}
	transforms_map['t1'] = conf.ComponentConfig{
		typ: 'remap'
		inputs: ['src1']
	}
	transforms_map['t2'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['t1']
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: transforms_map
		sinks: map[string]conf.ComponentConfig{}
	}
	order := resolve_transform_order(c) or { panic(err) }
	assert order.len == 2
	// t1 must come before t2
	assert order.index('t1') < order.index('t2')
}

fn test_resolve_transform_order_circular_dependency() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src1'] = conf.ComponentConfig{
		typ: 'stdin'
		inputs: []
	}

	mut transforms_map := map[string]conf.ComponentConfig{}
	transforms_map['t1'] = conf.ComponentConfig{
		typ: 'remap'
		inputs: ['t2'] // circular: t1 depends on t2
	}
	transforms_map['t2'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['t1'] // circular: t2 depends on t1
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: transforms_map
		sinks: map[string]conf.ComponentConfig{}
	}
	if _ := resolve_transform_order(c) {
		assert false, 'expected circular dependency error'
	}
}

fn test_topology_validation() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src1'] = conf.ComponentConfig{
		typ: 'stdin'
		inputs: []
	}

	mut sinks_map := map[string]conf.ComponentConfig{}
	sinks_map['sink1'] = conf.ComponentConfig{
		typ: 'console'
		inputs: ['src1']
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: map[string]conf.ComponentConfig{}
		sinks: sinks_map
	}
	c.validate_topology() or { panic(err) }
}

fn test_topology_validation_invalid_input() {
	mut sinks_map := map[string]conf.ComponentConfig{}
	sinks_map['sink1'] = conf.ComponentConfig{
		typ: 'console'
		inputs: ['nonexistent_source']
	}

	c := conf.PipelineConfig{
		sources: map[string]conf.ComponentConfig{}
		transforms: map[string]conf.ComponentConfig{}
		sinks: sinks_map
	}
	if _ := c.validate_topology() {
		assert false, 'expected error for invalid input reference'
	}
}
