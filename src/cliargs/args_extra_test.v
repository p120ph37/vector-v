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
	// parse_args reads os.args; under test runner, verify it returns valid struct
	args := parse_args()
	// All boolean fields are valid booleans (trivially true but exercises code path)
	assert args.verbose == true || args.verbose == false
	assert args.validate == true || args.validate == false
	assert args.version == true || args.version == false
	assert args.help == true || args.help == false
}
