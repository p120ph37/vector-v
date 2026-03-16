module sources

import event
import json
import net.http
import os
import time

// EcsMetricsSource scrapes the ECS task metadata endpoint for container stats
// and emits them as metric events. Mirrors Vector's aws_ecs_metrics source.
//
// Config options:
//   endpoint:             ECS metadata endpoint (default: from ECS_CONTAINER_METADATA_URI_V4
//                         env var, fallback to http://169.254.170.2/v4)
//   scrape_interval_secs: How often to scrape (default: 15)
//   namespace:            Metric namespace prefix (default: ecs)
pub struct EcsMetricsSource {
	endpoint        string
	scrape_interval time.Duration = 15 * time.second
	namespace       string = 'ecs'
}

// new_ecs_metrics creates a new EcsMetricsSource from config options.
pub fn new_ecs_metrics(opts map[string]string) EcsMetricsSource {
	mut endpoint := opts['endpoint'] or { '' }
	if endpoint.len == 0 {
		env_endpoint := os.getenv('ECS_CONTAINER_METADATA_URI_V4')
		if env_endpoint.len > 0 {
			endpoint = env_endpoint
		} else {
			endpoint = 'http://169.254.170.2/v4'
		}
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	namespace := opts['namespace'] or { 'ecs' }

	return EcsMetricsSource{
		endpoint: endpoint
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		namespace: namespace
	}
}

// run polls the ECS metadata endpoint and emits metric events.
pub fn (s &EcsMetricsSource) run(output chan event.Event) {
	for {
		s.scrape(output)
		time.sleep(s.scrape_interval)
	}
}

// DockerStats represents Docker container stats from the ECS metadata endpoint.
struct DockerStats {
	name         string         @[json: 'name']
	cpu_stats    DockerCpuStats @[json: 'cpu_stats']
	memory_stats DockerMemStats @[json: 'memory_stats']
	networks     map[string]DockerNetStats
}

struct DockerCpuStats {
	cpu_usage        DockerCpuUsage @[json: 'cpu_usage']
	system_cpu_usage f64            @[json: 'system_cpu_usage']
}

struct DockerCpuUsage {
	total_usage f64 @[json: 'total_usage']
}

struct DockerMemStats {
	usage f64
	limit f64
}

struct DockerNetStats {
	rx_bytes f64
	tx_bytes f64
}

fn (s &EcsMetricsSource) scrape(output chan event.Event) {
	url := '${s.endpoint}/task/stats'
	resp := http.fetch(http.FetchConfig{
		url: url
		method: .get
		verbose: false
	}) or {
		eprintln('aws_ecs_metrics: request failed: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('aws_ecs_metrics: HTTP ${resp.status_code} from ${url}')
		return
	}

	// The response is a JSON object keyed by container ID, each value is Docker stats.
	stats_map := json.decode(map[string]DockerStats, resp.body) or {
		eprintln('aws_ecs_metrics: failed to parse JSON: ${err}')
		return
	}

	for container_id, stats in stats_map {
		mut tags := {
			'container_id':   container_id
			'container_name': stats.name
		}

		// CPU metrics
		mut cpu_percent := 0.0
		if stats.cpu_stats.system_cpu_usage > 0 {
			cpu_percent = (stats.cpu_stats.cpu_usage.total_usage / stats.cpu_stats.system_cpu_usage) * 100.0
		}
		s.emit_gauge(output, '${s.namespace}.cpu.usage_percent', cpu_percent, tags)

		// Memory metrics
		s.emit_gauge(output, '${s.namespace}.memory.usage', stats.memory_stats.usage, tags)
		s.emit_gauge(output, '${s.namespace}.memory.limit', stats.memory_stats.limit, tags)

		// Network metrics
		mut total_rx := f64(0)
		mut total_tx := f64(0)
		for _, net_stats in stats.networks {
			total_rx += net_stats.rx_bytes
			total_tx += net_stats.tx_bytes
		}
		s.emit_counter(output, '${s.namespace}.network.rx_bytes', total_rx, tags)
		s.emit_counter(output, '${s.namespace}.network.tx_bytes', total_tx, tags)
	}
}

fn (s &EcsMetricsSource) emit_gauge(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_gauge(name, value)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'aws_ecs_metrics'
	output <- event.Event(m)
}

fn (s &EcsMetricsSource) emit_counter(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_counter(name, value, .incremental)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'aws_ecs_metrics'
	output <- event.Event(m)
}
