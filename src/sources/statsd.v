module sources

import event
import net
import time

// StatsdSource listens on a UDP or TCP socket and parses StatsD datagrams
// into Metric events. Supports DogStatsD tag extension format.
// Mirrors Vector's statsd source.
//
// StatsD line format: metric_name:value|type|@sample_rate|#tag1:val1,tag2:val2
// Types: c (counter), g (gauge), ms (timer), s (set), h (histogram)
//
// Config options:
//   mode:           "udp" or "tcp" (default: udp)
//   address:        Listen address (default: 0.0.0.0:8125)
pub struct StatsdSource {
	mode    StatsdMode
	address string = '0.0.0.0:8125'
}

enum StatsdMode {
	udp
	tcp
}

// new_statsd creates a new StatsdSource from config options.
pub fn new_statsd(opts map[string]string) StatsdSource {
	mode := match opts['mode'] or { 'udp' } {
		'tcp' { StatsdMode.tcp }
		else { StatsdMode.udp }
	}

	address := opts['address'] or { '0.0.0.0:8125' }

	return StatsdSource{
		mode: mode
		address: address
	}
}

// run starts listening and emitting metric events.
pub fn (s &StatsdSource) run(output chan event.Event) {
	match s.mode {
		.udp { s.run_udp(output) }
		.tcp { s.run_tcp(output) }
	}
}

fn (s &StatsdSource) run_udp(output chan event.Event) {
	mut conn := net.listen_udp(s.address) or {
		eprintln('statsd: failed to bind UDP ${s.address}: ${err}')
		return
	}
	eprintln('statsd: listening UDP on ${s.address}')

	for {
		mut buf := []u8{len: 65536}
		n, _ := conn.read(mut buf) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		if n == 0 {
			continue
		}
		data := buf[..n].bytestr().trim_right('\r\n')
		if data.len == 0 {
			continue
		}
		// A single UDP datagram may contain multiple newline-separated metrics
		for line in data.split('\n') {
			trimmed := line.trim_right('\r')
			if trimmed.len == 0 {
				continue
			}
			m := parse_statsd(trimmed) or {
				eprintln('statsd: parse error: ${err}')
				continue
			}
			output <- event.Event(m)
		}
	}
}

fn (s &StatsdSource) run_tcp(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('statsd: failed to bind TCP ${s.address}: ${err}')
		return
	}
	eprintln('statsd: listening TCP on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		spawn handle_statsd_tcp(mut conn, output)
	}
}

fn handle_statsd_tcp(mut conn net.TcpConn, output chan event.Event) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	mut sb := new_socket_buffer(102400)

	for {
		mut buf := []u8{len: 8192}
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		sb.feed(buf[..n])
		for line in sb.read_lines() {
			if line.len == 0 {
				continue
			}
			m := parse_statsd(line) or {
				eprintln('statsd: parse error: ${err}')
				continue
			}
			output <- event.Event(m)
		}
	}

	// Flush remaining
	remaining := sb.remaining()
	if remaining.len > 0 {
		m := parse_statsd(remaining) or { return }
		output <- event.Event(m)
	}
}

// parse_statsd parses a single StatsD line into a Metric event.
// Format: metric_name:value|type|@sample_rate|#tag1:val1,tag2:val2
fn parse_statsd(line string) !event.Metric {
	// Split name from rest: name:value|type|...
	colon := line.index(':') or { return error('missing colon in statsd line: ${line}') }
	name := line[..colon]
	if name.len == 0 {
		return error('empty metric name')
	}
	rest := line[colon + 1..]

	// Split by pipe: value, type, optional @sample_rate, optional #tags
	parts := rest.split('|')
	if parts.len < 2 {
		return error('missing type in statsd line: ${line}')
	}

	val_str := parts[0]
	typ := parts[1]

	mut sample_rate := 1.0
	mut tags := map[string]string{}

	for i := 2; i < parts.len; i++ {
		part := parts[i]
		if part.starts_with('@') {
			sample_rate = part[1..].f64()
			if sample_rate <= 0 || sample_rate > 1.0 {
				sample_rate = 1.0
			}
		} else if part.starts_with('#') {
			tag_str := part[1..]
			for tag in tag_str.split(',') {
				eq := tag.index(':') or { -1 }
				if eq >= 0 {
					tags[tag[..eq]] = tag[eq + 1..]
				} else {
					tags[tag] = ''
				}
			}
		}
	}

	mut m := event.Metric{
		name: name
		tags: tags
		timestamp: time.now()
		meta: event.EventMetadata{
			source_type: 'statsd'
		}
	}

	match typ {
		'c' {
			val := val_str.f64()
			m.kind = .incremental
			m.value = event.CounterValue{
				value: val
			}
		}
		'g' {
			val := val_str.f64()
			m.kind = .absolute
			m.value = event.GaugeValue{
				value: val
			}
		}
		's' {
			m.kind = .incremental
			m.value = event.SetValue{
				values: [val_str]
			}
		}
		'ms', 'h' {
			val := val_str.f64()
			rate := u32(1.0 / sample_rate)
			m.kind = .incremental
			m.value = event.DistributionValue{
				samples: [event.Sample{
					value: val
					rate: if rate == 0 { u32(1) } else { rate }
				}]
				statistic: .histogram
			}
		}
		else {
			return error('unknown statsd metric type: ${typ}')
		}
	}

	return m
}
