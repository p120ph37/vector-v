module sinks

import event

// Sink is a tagged union of all sink types.
pub type Sink = ConsoleSink
	| BlackholeSink
	| LokiSink
	| OpenTelemetrySink
	| CloudWatchLogsSink
	| CloudWatchMetricsSink
	| HttpSink
	| FileSink
	| S3Sink
	| WebSocketSink

// build_sink creates a Sink from a type name and config options.
pub fn build_sink(typ string, opts map[string]string) !Sink {
	match typ {
		'console' {
			return Sink(new_console(opts))
		}
		'blackhole' {
			return Sink(new_blackhole(opts))
		}
		'loki' {
			return Sink(new_loki(opts))
		}
		'opentelemetry' {
			return Sink(new_opentelemetry(opts))
		}
		'aws_cloudwatch_logs' {
			return Sink(new_cloudwatch_logs(opts)!)
		}
		'aws_cloudwatch_metrics' {
			return Sink(new_cloudwatch_metrics(opts)!)
		}
		'http' {
			return Sink(new_http(opts))
		}
		'file' {
			return Sink(new_file(opts)!)
		}
		'aws_s3' {
			return Sink(new_s3(opts)!)
		}
		'websocket' {
			return Sink(new_websocket(opts)!)
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
		LokiSink {
			mut ls := s
			ls.send(e)!
		}
		OpenTelemetrySink {
			mut os := s
			os.send(e)!
		}
		CloudWatchLogsSink {
			mut cs := s
			cs.send(e)!
		}
		CloudWatchMetricsSink {
			mut ms := s
			ms.send(e)!
		}
		HttpSink {
			mut hs := s
			hs.send(e)!
		}
		FileSink {
			mut fs := s
			fs.send(e)!
		}
		S3Sink {
			mut ss := s
			ss.send(e)!
		}
		WebSocketSink {
			mut ws := s
			ws.send(e)!
		}
	}
}
