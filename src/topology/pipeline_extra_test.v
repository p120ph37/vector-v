module topology

import conf

fn test_pipeline_new() {
	c := conf.PipelineConfig{}
	p := new(c)
	assert p.cfg.sources.len == 0
	assert p.cfg.transforms.len == 0
	assert p.cfg.sinks.len == 0
}

fn test_pipeline_new_with_components() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src'] = conf.ComponentConfig{
		typ: 'stdin'
	}
	mut sinks_map := map[string]conf.ComponentConfig{}
	sinks_map['out'] = conf.ComponentConfig{
		typ: 'console'
		inputs: ['src']
	}
	c := conf.PipelineConfig{
		sources: sources_map
		sinks: sinks_map
	}
	p := new(c)
	assert p.cfg.sources.len == 1
	assert p.cfg.sinks.len == 1
}

fn test_resolve_transform_order_fan_in() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src1'] = conf.ComponentConfig{
		typ: 'stdin'
	}
	sources_map['src2'] = conf.ComponentConfig{
		typ: 'demo_logs'
	}

	mut transforms_map := map[string]conf.ComponentConfig{}
	transforms_map['merge'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['src1', 'src2']
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: transforms_map
	}
	order := resolve_transform_order(c) or { panic(err) }
	assert order.len == 1
	assert order[0] == 'merge'
}

fn test_resolve_transform_order_diamond() {
	mut sources_map := map[string]conf.ComponentConfig{}
	sources_map['src'] = conf.ComponentConfig{
		typ: 'stdin'
	}

	mut transforms_map := map[string]conf.ComponentConfig{}
	transforms_map['a'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['src']
	}
	transforms_map['b'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['src']
	}
	transforms_map['c'] = conf.ComponentConfig{
		typ: 'filter'
		inputs: ['a', 'b']
	}

	c := conf.PipelineConfig{
		sources: sources_map
		transforms: transforms_map
	}
	order := resolve_transform_order(c) or { panic(err) }
	assert order.len == 3
	// c must come after both a and b
	assert order.index('c') > order.index('a')
	assert order.index('c') > order.index('b')
}
