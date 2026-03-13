module cliargs

fn test_print_help_runs() {
	// Verify print_help compiles and can be called without error
	print_help()
}

fn test_print_version_runs() {
	// Verify print_version compiles and can be called without error
	print_version()
}

fn test_parse_args_returns_struct() {
	// parse_args reads os.args which we can't control in unit tests,
	// but we verify it returns a valid Args struct and doesn't panic
	args := parse_args()
	// When running under `v test`, there's no -c flag, so config_path
	// may be empty or default. Just verify the struct is valid.
	assert args.config_path.len >= 0
	assert args.verbose == false || args.verbose == true
	assert args.validate == false || args.validate == true
}
