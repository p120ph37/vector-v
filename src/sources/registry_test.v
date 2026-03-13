module sources

fn test_build_source_stdin() {
	s := build_source('stdin', map[string]string{}) or { panic(err) }
	assert s is StdinSource
}

fn test_build_source_demo_logs() {
	s := build_source('demo_logs', map[string]string{}) or { panic(err) }
	assert s is DemoLogsSource
}

fn test_build_source_fluent() {
	s := build_source('fluent', map[string]string{}) or { panic(err) }
	assert s is FluentSource
}

fn test_build_source_unknown_errors() {
	if _ := build_source('nonexistent', map[string]string{}) {
		assert false, 'expected error for unknown source type'
	}
}
