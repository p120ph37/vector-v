module sources

import event
import time
import rand

// DemoLogsSource generates sample log events for testing.
// Mirrors Vector's demo_logs source.
pub struct DemoLogsSource {
	format   string = 'text'
	count    int    = 10
	interval f64    = 1.0
}

// new_demo_logs creates a new DemoLogsSource from config options.
pub fn new_demo_logs(opts map[string]string) DemoLogsSource {
	mut format := 'text'
	if f := opts['format'] {
		format = f
	}
	mut count := 10
	if c := opts['count'] {
		count = c.int()
		if count <= 0 {
			count = 10
		}
	}
	mut interval := 1.0
	if i := opts['interval'] {
		interval = i.f64()
		if interval <= 0 {
			interval = 1.0
		}
	}
	return DemoLogsSource{
		format: format
		count: count
		interval: interval
	}
}

const sample_messages = [
	'Vector is running normally',
	'Processing batch of events',
	'Connection established',
	'Flushing buffer to sink',
	'Health check passed',
	'Pipeline topology validated',
	'Event received from source',
	'Transform applied successfully',
	'Sink acknowledged batch',
	'Configuration reloaded',
]

// run generates demo log events and sends them to the output channel.
pub fn (s &DemoLogsSource) run(output chan event.Event) {
	for i := 0; i < s.count; i++ {
		msg := match s.format {
			'syslog' {
				now := time.now()
				'<34>1 ${now.format_rfc3339()} vector-v demo - - - ${sources.sample_messages[i % sources.sample_messages.len]}'
			}
			'json' {
				'{"timestamp":"${time.now().format_rfc3339()}","level":"info","message":"${sources.sample_messages[i % sources.sample_messages.len]}","host":"vector-v","pid":${rand.intn(9999) or {
					1000
				}}}'
			}
			else {
				'${time.now().format_rfc3339()} INFO ${sources.sample_messages[i % sources.sample_messages.len]}'
			}
		}

		mut ev := event.new_log(msg)
		ev.meta.source_type = 'demo_logs'
		output <- event.Event(ev)

		if i < s.count - 1 {
			time.sleep(time.Duration(i64(s.interval * 1_000_000_000)))
		}
	}
}
