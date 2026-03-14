module cliargs

import os

// Args holds the parsed command-line arguments.
pub struct Args {
pub:
	config_path string // -c or --config
	verbose     bool   // -v or --verbose
	validate    bool   // --validate (validate config only, don't run)
	version     bool   // --version
	help        bool   // -h or --help
}

// parse_args parses command-line arguments from os.args.
pub fn parse_args() Args {
	return parse_args_from(os.args[1..])
}

// parse_args_from parses a list of argument strings into Args.
pub fn parse_args_from(args []string) Args {
	mut config_path := ''
	mut verbose := false
	mut validate := false
	mut version := false
	mut help := false

	mut i := 0
	for i < args.len {
		arg := args[i]
		match arg {
			'-c', '--config' {
				if i + 1 < args.len {
					i++
					config_path = args[i]
				}
			}
			'-v', '--verbose' {
				verbose = true
			}
			'--validate' {
				validate = true
			}
			'--version' {
				version = true
			}
			'-h', '--help' {
				help = true
			}
			else {
				// If no flag prefix and no config yet, treat as config path
				if !arg.starts_with('-') && config_path.len == 0 {
					config_path = arg
				}
			}
		}
		i++
	}

	// Default config path
	if config_path.len == 0 && !version && !help {
		// Try common defaults
		for path in ['vector.toml', '/etc/vector/vector.toml'] {
			if os.exists(path) {
				config_path = path
				break
			}
		}
	}

	return Args{
		config_path: config_path
		verbose: verbose
		validate: validate
		version: version
		help: help
	}
}

// print_help displays usage information.
pub fn print_help() {
	println('vector-v - A V-lang port of Vector (high-performance observability data pipeline)')
	println('')
	println('USAGE:')
	println('    vector-v [OPTIONS]')
	println('')
	println('OPTIONS:')
	println('    -c, --config <PATH>    Path to configuration file [default: vector.toml]')
	println('    -v, --verbose          Enable verbose logging')
	println('    --validate             Validate configuration and exit')
	println('    --version              Print version information')
	println('    -h, --help             Print help information')
	println('')
	println('EXAMPLES:')
	println('    echo "hello" | vector-v -c pipeline.toml')
	println('    vector-v --config /etc/vector-v/vector.toml')
	println('    vector-v --validate -c vector.toml')
}

// print_version displays version information.
pub fn print_version() {
	println('vector-v 0.1.0 (V-lang port of Vector)')
}
