module sinks

import event

// Sink is a tagged union of all sink types.
pub type Sink = ConsoleSink | BlackholeSink

// build_sink creates a Sink from a type name and config options.
pub fn build_sink(typ string, opts map[string]string) !Sink {
	match typ {
		'console' {
			return Sink(new_console(opts))
		}
		'blackhole' {
			return Sink(new_blackhole(opts))
		}
		else {
			return error('unknown sink type: "${typ}"')
		}
	}
}

// send_to_sink dispatches an event to the appropriate sink.
pub fn send_to_sink(s Sink, e event.Event) ! {
	match s {
		ConsoleSink {
			s.send(e)!
		}
		BlackholeSink {
			mut bs := s
			bs.send(e)!
		}
	}
}
