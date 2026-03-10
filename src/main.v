module main

import os
import cliargs
import api
import conf
import topology

fn main() {
	args := cliargs.parse_args()

	if args.help {
		cliargs.print_help()
		return
	}

	if args.version {
		cliargs.print_version()
		return
	}

	if args.config_path.len == 0 {
		eprintln('error: no configuration file specified')
		eprintln('usage: vector-v -c <config.toml>')
		eprintln('run vector-v --help for more information')
		exit(1)
	}

	content := os.read_file(args.config_path) or {
		eprintln('error: could not read config file "${args.config_path}": ${err}')
		exit(1)
	}

	if args.verbose {
		eprintln('info: loading config from ${args.config_path}')
	}

	pipeline_cfg := conf.parse_toml_config(content) or {
		eprintln('error: invalid configuration: ${err}')
		exit(1)
	}

	pipeline_cfg.validate_topology() or {
		eprintln('error: invalid topology: ${err}')
		exit(1)
	}

	if args.validate {
		println('Configuration is valid.')
		println('  Sources:    ${pipeline_cfg.sources.len}')
		println('  Transforms: ${pipeline_cfg.transforms.len}')
		println('  Sinks:      ${pipeline_cfg.sinks.len}')
		return
	}

	if args.verbose {
		eprintln('info: starting pipeline with ${pipeline_cfg.sources.len} source(s), ${pipeline_cfg.transforms.len} transform(s), ${pipeline_cfg.sinks.len} sink(s)')
	}

	// Start API server if configured
	// Check if any source has api.enabled = true or if there's an api section
	mut api_enabled := false
	mut api_address := '0.0.0.0:8686'
	for _, comp in pipeline_cfg.sources {
		if ae := comp.options['api.enabled'] {
			if ae == 'true' {
				api_enabled = true
			}
		}
		if aa := comp.options['api.address'] {
			api_address = aa
		}
	}

	if api_enabled {
		spawn api.run_server(api_address)
	}

	pipeline := topology.new(pipeline_cfg)
	pipeline.run() or {
		eprintln('error: pipeline failed: ${err}')
		exit(1)
	}
}
