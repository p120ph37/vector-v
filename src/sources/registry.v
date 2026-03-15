module sources

import event

// Source is a tagged union of all source types.
pub type Source = StdinSource
	| DemoLogsSource
	| FluentSource
	| ExecSource
	| FileDescriptorSource
	| HttpClientSource
	| SocketSource
	| WebSocketSource
	| VectorSource

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
		'exec' {
			return Source(new_exec(opts)!)
		}
		'file_descriptors' {
			return Source(new_file_descriptor(opts))
		}
		'http_client' {
			return Source(new_http_client(opts)!)
		}
		'socket' {
			return Source(new_socket(opts))
		}
		'websocket' {
			return Source(new_websocket_source(opts)!)
		}
		'vector' {
			return Source(new_vector_source(opts))
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
		ExecSource {
			s.run(output)
		}
		FileDescriptorSource {
			s.run(output)
		}
		HttpClientSource {
			s.run(output)
		}
		SocketSource {
			s.run(output)
		}
		WebSocketSource {
			s.run(output)
		}
		VectorSource {
			s.run(output)
		}
	}
}
