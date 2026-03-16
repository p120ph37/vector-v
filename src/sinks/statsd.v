module sinks

import event
import net
import time

// StatsdSink sends metric events to a StatsD server over UDP or TCP.
// Mirrors Vector's statsd sink.
//
// Encodes metrics as StatsD line format: name:value|type|#tags
// Only processes Metric events; LogEvent and TraceEvent are silently dropped.
//
// Config options:
//   mode:                "udp" or "tcp" (default: udp)
//   address:             Target address (default: 127.0.0.1:8125)
//   default_namespace:   Namespace prefix for metrics without one (default: "")
//   batch.max_events:    Max events before flush (default: 100)
//   batch.timeout_secs:  Max seconds before flush (default: 1)
pub struct StatsdSink {
	mode              StatsdSinkMode
	address           string
	default_namespace string
	batch_max         int = 100
	batch_timeout     time.Duration = 1 * time.second
mut:
	tcp_fd     int = -1
	connected  bool
	buffer     []string
	last_flush time.Time
}

enum StatsdSinkMode {
	udp
	tcp
}

// new_statsd_sink creates a new StatsdSink from config options.
pub fn new_statsd_sink(opts map[string]string) !StatsdSink {
	address := opts['address'] or { '127.0.0.1:8125' }

	mode := match opts['mode'] or { 'udp' } {
		'tcp' { StatsdSinkMode.tcp }
		else { StatsdSinkMode.udp }
	}

	default_namespace := opts['default_namespace'] or { '' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return StatsdSink{
		mode: mode
		address: address
		default_namespace: default_namespace
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers a metric event and flushes when batch is full or timeout expires.
// LogEvent and TraceEvent are silently dropped.
pub fn (mut s StatsdSink) send(e event.Event) ! {
	match e {
		event.Metric {
			lines := format_statsd(e, s.default_namespace)
			for line in lines {
				s.buffer << line
			}

			if s.buffer.len >= s.batch_max {
				s.flush()!
			}

			if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
				s.flush()!
			}
		}
		event.LogEvent {}
		event.TraceEvent {}
	}
}

// flush sends all buffered lines to the StatsD server.
pub fn (mut s StatsdSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	match s.mode {
		.udp { s.flush_udp()! }
		.tcp { s.flush_tcp()! }
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (mut s StatsdSink) flush_udp() ! {
	mut conn := net.dial_udp(s.address) or {
		return error('statsd sink: UDP dial failed: ${err}')
	}
	defer { conn.close() or {} }

	// Send each line as a separate UDP datagram (standard StatsD behavior)
	// or combine into a single datagram separated by newlines if small enough
	payload := s.buffer.join('\n')
	conn.write(payload.bytes()) or {
		return error('statsd sink: UDP send failed: ${err}')
	}
}

fn (mut s StatsdSink) flush_tcp() ! {
	if !s.connected {
		s.connect_tcp() or {
			return error('statsd sink: connection failed: ${err}')
		}
	}

	payload := s.buffer.join('\n') + '\n'

	s.write_tcp(payload) or {
		// Try reconnect once
		s.connected = false
		s.connect_tcp() or {
			return error('statsd sink: reconnection failed: ${err}')
		}
		s.write_tcp(payload) or {
			s.connected = false
			return error('statsd sink: send failed after reconnect: ${err}')
		}
	}
}

fn (mut s StatsdSink) connect_tcp() ! {
	if s.tcp_fd >= 0 {
		C.close(s.tcp_fd)
		s.tcp_fd = -1
	}

	mut conn := net.dial_tcp(s.address) or {
		return error('tcp connect to ${s.address} failed: ${err}')
	}
	conn.set_write_timeout(5 * time.second)
	s.tcp_fd = conn.sock.handle
	s.connected = true
}

fn (mut s StatsdSink) write_tcp(data string) ! {
	if s.tcp_fd < 0 {
		return error('not connected')
	}
	bytes := data.bytes()
	sent := C.send(s.tcp_fd, bytes.data, bytes.len, 0)
	if sent < 0 {
		return error('write failed: socket error')
	}
}

// close closes the TCP connection (no-op for UDP).
pub fn (mut s StatsdSink) close() {
	if s.tcp_fd >= 0 {
		C.close(s.tcp_fd)
		s.tcp_fd = -1
	}
	s.connected = false
}

// total_buffered returns the number of lines currently buffered.
pub fn (s &StatsdSink) total_buffered() int {
	return s.buffer.len
}

// format_statsd encodes a Metric as one or more StatsD line-protocol strings.
// Format: name:value|type|#tag1:val1,tag2:val2
fn format_statsd(m event.Metric, default_namespace string) []string {
	// Build full metric name with namespace prefix
	ns := if m.namespace.len > 0 {
		m.namespace
	} else {
		default_namespace
	}
	full_name := if ns.len > 0 { '${ns}.${m.name}' } else { m.name }

	// Build tag suffix
	tag_suffix := statsd_format_tags(m.tags)

	mut lines := []string{}

	match m.value {
		event.CounterValue {
			lines << '${full_name}:${m.value.value}|c${tag_suffix}'
		}
		event.GaugeValue {
			lines << '${full_name}:${m.value.value}|g${tag_suffix}'
		}
		event.SetValue {
			// One line per set value
			for v in m.value.values {
				lines << '${full_name}:${v}|s${tag_suffix}'
			}
		}
		event.DistributionValue {
			// One line per sample
			for sample in m.value.samples {
				lines << '${full_name}:${sample.value}|h${tag_suffix}'
			}
		}
		event.HistogramValue {
			// Emit as distribution histogram
			lines << '${full_name}:${m.value.sum}|h${tag_suffix}'
		}
		event.SummaryValue {
			// Emit summary sum as histogram
			lines << '${full_name}:${m.value.sum}|h${tag_suffix}'
		}
	}

	return lines
}

// statsd_format_tags builds the DogStatsD tag suffix: |#tag1:val1,tag2:val2
fn statsd_format_tags(tags map[string]string) string {
	if tags.len == 0 {
		return ''
	}
	mut parts := []string{}
	for k, v in tags {
		if v.len > 0 {
			parts << '${k}:${v}'
		} else {
			parts << k
		}
	}
	return '|#${parts.join(',')}'
}
