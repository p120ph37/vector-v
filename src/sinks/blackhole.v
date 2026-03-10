module sinks

import event

// BlackholeSink discards all events. Useful for benchmarking.
// Mirrors Vector's blackhole sink.
pub struct BlackholeSink {
pub mut:
	count u64
}

// new_blackhole creates a new BlackholeSink.
pub fn new_blackhole(_opts map[string]string) BlackholeSink {
	return BlackholeSink{}
}

// send consumes an event and discards it, incrementing the counter.
pub fn (mut s BlackholeSink) send(_e event.Event) ! {
	s.count++
}
