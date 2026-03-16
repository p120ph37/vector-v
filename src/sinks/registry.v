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
	| VectorSink
	| SocketSink
	| StatsdSink
	| PrometheusSink
	| KinesisSink
	| KinesisFirehoseSink
	| SqsSink

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
		'vector' {
			return Sink(new_vector(opts))
		}
		'socket' {
			return Sink(new_socket_sink(opts)!)
		}
		'statsd' {
			return Sink(new_statsd_sink(opts)!)
		}
		'prometheus', 'prometheus_remote_write' {
			return Sink(new_prometheus_sink(opts)!)
		}
		'aws_kinesis_streams' {
			return Sink(new_kinesis(opts)!)
		}
		'aws_kinesis_firehose' {
			return Sink(new_kinesis_firehose(opts)!)
		}
		'aws_sqs' {
			return Sink(new_sqs(opts)!)
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
		VectorSink {
			mut vs := s
			vs.send(e)!
		}
		SocketSink {
			mut sks := s
			sks.send(e)!
		}
		StatsdSink {
			mut ss := s
			ss.send(e)!
		}
		PrometheusSink {
			mut ps := s
			ps.send(e)!
		}
		KinesisSink {
			mut ks := s
			ks.send(e)!
		}
		KinesisFirehoseSink {
			mut kfs := s
			kfs.send(e)!
		}
		SqsSink {
			mut sqs := s
			sqs.send(e)!
		}
	}
}
