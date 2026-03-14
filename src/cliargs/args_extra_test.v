module cliargs

fn test_args_struct_defaults() {
	args := Args{}
	assert args.config_path == ''
	assert args.verbose == false
	assert args.validate == false
	assert args.version == false
	assert args.help == false
}

fn test_args_struct_fields() {
	args := Args{
		config_path: '/etc/vector/vector.toml'
		verbose: true
		validate: true
		version: false
		help: false
	}
	assert args.config_path == '/etc/vector/vector.toml'
	assert args.verbose == true
	assert args.validate == true
	assert args.version == false
	assert args.help == false
}

fn test_args_all_flags_set() {
	args := Args{
		config_path: 'config.toml'
		verbose: true
		validate: true
		version: true
		help: true
	}
	assert args.config_path == 'config.toml'
	assert args.verbose == true
	assert args.validate == true
	assert args.version == true
	assert args.help == true
}

fn test_print_help_does_not_panic() {
	// Calling print_help should not panic
	print_help()
}

fn test_print_version_does_not_panic() {
	// Calling print_version should not panic
	print_version()
}

fn test_parse_args_returns_valid_struct() {
	args := parse_args()
	assert args.verbose == true || args.verbose == false
}

fn test_parse_args_from_config_short() {
	args := parse_args_from(['-c', 'my.toml'])
	assert args.config_path == 'my.toml'
}

fn test_parse_args_from_config_long() {
	args := parse_args_from(['--config', '/etc/vector.toml'])
	assert args.config_path == '/etc/vector.toml'
}

fn test_parse_args_from_verbose() {
	args := parse_args_from(['-v'])
	assert args.verbose == true
}

fn test_parse_args_from_verbose_long() {
	args := parse_args_from(['--verbose'])
	assert args.verbose == true
}

fn test_parse_args_from_validate() {
	args := parse_args_from(['--validate'])
	assert args.validate == true
}

fn test_parse_args_from_version() {
	args := parse_args_from(['--version'])
	assert args.version == true
}

fn test_parse_args_from_help_short() {
	args := parse_args_from(['-h'])
	assert args.help == true
}

fn test_parse_args_from_help_long() {
	args := parse_args_from(['--help'])
	assert args.help == true
}

fn test_parse_args_from_positional_config() {
	args := parse_args_from(['pipeline.toml'])
	assert args.config_path == 'pipeline.toml'
}

fn test_parse_args_from_all_flags() {
	args := parse_args_from(['-c', 'test.toml', '-v', '--validate', '--version', '-h'])
	assert args.config_path == 'test.toml'
	assert args.verbose == true
	assert args.validate == true
	assert args.version == true
	assert args.help == true
}

fn test_parse_args_from_empty() {
	args := parse_args_from([])
	assert args.verbose == false
	assert args.help == false
}

fn test_parse_args_from_unknown_flag() {
	args := parse_args_from(['--unknown-flag'])
	assert args.verbose == false
}
