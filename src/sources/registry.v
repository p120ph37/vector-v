module sources

import event

// Source is a tagged union of all source types.
pub type Source = StdinSource | DemoLogsSource | FluentSource

// build_source creates a Source from a type name and config options.
pub fn build_source(typ string, opts map[string]string) !Source {
	match typ {
		'stdin' {
			return Source(new_stdin(opts))
		}
		'demo_logs' {
			return Source(new_demo_logs(opts))
		}
		'fluent' {
			return Source(new_fluent(opts))
		}
		else {
			return error('unknown source type: "${typ}"')
		}
	}
}

// run_source dispatches to the appropriate source's run method.
pub fn run_source(s Source, output chan event.Event) {
	match s {
		StdinSource {
			s.run(output)
		}
		DemoLogsSource {
			s.run(output)
		}
		FluentSource {
			s.run(output)
		}
	}
}
