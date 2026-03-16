module sources

import event
import json
import net.http
import os
import time

// DockerLogsSource collects logs from Docker containers via the Docker Engine API.
// Mirrors Vector's docker_logs source (src/sources/docker_logs/).
//
// The source communicates with Docker via its HTTP API. By default it uses the
// Unix socket at /var/run/docker.sock, but can be configured to use a TCP endpoint.
//
// Config options:
//   docker_host:          Docker daemon endpoint (default: unix:///var/run/docker.sock)
//   include_containers:   Comma-separated container name/ID filters
//   exclude_containers:   Comma-separated exclusion filters
//   include_images:       Comma-separated image name filters
//   include_labels:       Comma-separated label filters
//   auto_partial_merge:   Merge partial Docker log lines (default: true)
//   host_key:             Field name for host metadata (default: "host")
//   partial_merge_field:  Field name for partial merge tracking (default: "_partial")
//   retry_backoff_secs:   Retry delay on failure (default: 2.0)
//   since:                Docker API since parameter (RFC3339 or Unix timestamp)
pub struct DockerLogsSource {
	docker_host         string   = 'unix:///var/run/docker.sock'
	include_containers  []string // filter: only these container names/IDs
	exclude_containers  []string // filter: exclude these container names/IDs
	include_images      []string // filter: only containers from these images
	include_labels      []string // filter: only containers with these labels
	auto_partial_merge  bool     = true
	host_key            string   = 'host'
	partial_merge_field string   = '_partial'
	retry_backoff_secs  f64      = 2.0
	since               string   // Docker API since parameter (RFC3339 or Unix timestamp)
}

// DockerContainer represents a container from the Docker API /containers/json response.
pub struct DockerContainer {
pub:
	id     string            @[json: 'Id']
	names  []string          @[json: 'Names']
	image  string            @[json: 'Image']
	labels map[string]string @[json: 'Labels']
	state  string            @[json: 'State']
	status string            @[json: 'Status']
}

// new_docker_logs creates a new DockerLogsSource from config options.
pub fn new_docker_logs(opts map[string]string) DockerLogsSource {
	mut docker_host := 'unix:///var/run/docker.sock'
	if h := opts['docker_host'] {
		if h.len > 0 {
			docker_host = h
		}
	}

	mut include_containers := []string{}
	if ic := opts['include_containers'] {
		for part in ic.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				include_containers << trimmed
			}
		}
	}

	mut exclude_containers := []string{}
	if ec := opts['exclude_containers'] {
		for part in ec.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				exclude_containers << trimmed
			}
		}
	}

	mut include_images := []string{}
	if ii := opts['include_images'] {
		for part in ii.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				include_images << trimmed
			}
		}
	}

	mut include_labels := []string{}
	if il := opts['include_labels'] {
		for part in il.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				include_labels << trimmed
			}
		}
	}

	mut auto_partial_merge := true
	if apm := opts['auto_partial_merge'] {
		auto_partial_merge = apm == 'true'
	}

	mut host_key := 'host'
	if hk := opts['host_key'] {
		if hk.len > 0 {
			host_key = hk
		}
	}

	mut partial_merge_field := '_partial'
	if pmf := opts['partial_merge_field'] {
		if pmf.len > 0 {
			partial_merge_field = pmf
		}
	}

	mut retry_backoff_secs := 2.0
	if rbs := opts['retry_backoff_secs'] {
		retry_backoff_secs = rbs.f64()
		if retry_backoff_secs <= 0 {
			retry_backoff_secs = 2.0
		}
	}

	since := opts['since'] or { '' }

	return DockerLogsSource{
		docker_host: docker_host
		include_containers: include_containers
		exclude_containers: exclude_containers
		include_images: include_images
		include_labels: include_labels
		auto_partial_merge: auto_partial_merge
		host_key: host_key
		partial_merge_field: partial_merge_field
		retry_backoff_secs: retry_backoff_secs
		since: since
	}
}

// run is the main loop that polls Docker for containers and their logs.
// It periodically lists containers, filters them, fetches recent logs,
// parses each line, and emits LogEvents to the output channel.
pub fn (s &DockerLogsSource) run(output chan event.Event) {
	hostname := os.hostname() or { 'unknown' }
	mut known_containers := map[string]bool{}
	mut last_timestamps := map[string]string{} // container_id -> last seen timestamp

	for {
		containers := s.fetch_container_list() or {
			eprintln('docker_logs: failed to list containers: ${err}')
			time.sleep(time.Duration(i64(s.retry_backoff_secs * 1_000_000_000)))
			continue
		}

		for c in containers {
			container_name := if c.names.len > 0 {
				c.names[0].trim_left('/')
			} else {
				c.id[..12]
			}

			if !matches_container_filter(container_name, c.image, c.labels, s.include_containers,
				s.exclude_containers, s.include_images, s.include_labels) {
				continue
			}

			since_param := if last_ts := last_timestamps[c.id] {
				last_ts
			} else if s.since.len > 0 {
				s.since
			} else {
				''
			}

			log_lines := s.fetch_container_logs(c.id, since_param) or {
				eprintln('docker_logs: failed to fetch logs for ${container_name}: ${err}')
				continue
			}

			metadata := build_container_metadata(c)

			for line in log_lines {
				if line.trim_space().len == 0 {
					continue
				}

				ts, stream, message := parse_docker_log_line(line) or { continue }

				mut ev := event.new_log(message)
				ev.meta.source_type = 'docker_logs'
				ev.set('container_id', event.Value(c.id))
				ev.set('container_name', event.Value(container_name))
				ev.set('image', event.Value(c.image))
				ev.set('stream', event.Value(stream))
				ev.set('timestamp', event.Value(ts))
				ev.set(s.host_key, event.Value(hostname))

				for mk, mv in metadata {
					ev.set(mk, event.Value(mv))
				}

				output <- event.Event(ev)

				// Track last timestamp for incremental fetching
				if ts.len > 0 {
					last_timestamps[c.id] = ts
				}
			}

			known_containers[c.id] = true
		}

		// Remove containers that are no longer running
		for id, _ in known_containers {
			mut found := false
			for c in containers {
				if c.id == id {
					found = true
					break
				}
			}
			if !found {
				known_containers.delete(id)
				last_timestamps.delete(id)
			}
		}

		time.sleep(time.Duration(i64(s.retry_backoff_secs * 1_000_000_000)))
	}
}

// fetch_container_list retrieves the list of running containers from the Docker API.
fn (s &DockerLogsSource) fetch_container_list() ![]DockerContainer {
	url := docker_api_url(s.docker_host, '/containers/json')
	resp := http.fetch(http.FetchConfig{
		url: url
		method: .get
		verbose: false
	})!

	if resp.status_code >= 400 {
		return error('HTTP ${resp.status_code}: ${resp.body}')
	}

	containers := json.decode([]DockerContainer, resp.body)!
	return containers
}

// fetch_container_logs retrieves log lines for a specific container.
fn (s &DockerLogsSource) fetch_container_logs(container_id string, since string) ![]string {
	mut query := 'stdout=true&stderr=true&timestamps=true'
	if since.len > 0 {
		query += '&since=${since}'
	}

	url := docker_api_url(s.docker_host, '/containers/${container_id}/logs?${query}')
	resp := http.fetch(http.FetchConfig{
		url: url
		method: .get
		verbose: false
	})!

	if resp.status_code >= 400 {
		return error('HTTP ${resp.status_code}: ${resp.body}')
	}

	mut lines := []string{}
	for line in resp.body.split('\n') {
		if line.trim_space().len > 0 {
			lines << line
		}
	}
	return lines
}

// docker_api_url constructs the full API URL from the docker_host and path.
// For unix:// hosts, it converts to http://localhost since V's http client
// doesn't support Unix sockets directly — users should use TCP endpoints
// or a proxy for production use.
fn docker_api_url(docker_host string, path string) string {
	if docker_host.starts_with('unix://') {
		// V's HTTP client doesn't support Unix sockets directly.
		// Fall back to localhost — in production, users can configure
		// docker_host to a TCP endpoint or use socat/proxy.
		return 'http://localhost${path}'
	}
	if docker_host.starts_with('tcp://') {
		return 'http://' + docker_host[6..] + path
	}
	if docker_host.starts_with('http://') || docker_host.starts_with('https://') {
		return docker_host + path
	}
	return 'http://${docker_host}${path}'
}

// parse_docker_log_line parses a Docker log line in the format:
//   "2024-01-01T00:00:00.000000000Z stdout F message text here"
// or the simpler format:
//   "2024-01-01T00:00:00.000000000Z stdout message text here"
// Returns (timestamp, stream, message).
pub fn parse_docker_log_line(line string) ?(string, string, string) {
	// Docker log lines start with an RFC3339Nano timestamp, then stream, then message.
	// Format: <timestamp> <stream> [F|P] <message>
	// The F/P indicator is optional (F=full, P=partial).

	// Find first space — separates timestamp
	first_space := line.index(' ') or { return none }
	if first_space == 0 || first_space >= line.len - 1 {
		return none
	}

	timestamp := line[..first_space]

	// Validate timestamp looks like ISO8601/RFC3339
	if timestamp.len < 10 || !timestamp.contains_any('T-') {
		return none
	}

	rest := line[first_space + 1..]

	// Find second space — separates stream name
	second_space := rest.index(' ') or { return none }
	if second_space == 0 {
		return none
	}

	stream := rest[..second_space]

	// stream should be "stdout" or "stderr"
	if stream != 'stdout' && stream != 'stderr' {
		return none
	}

	mut message := rest[second_space + 1..]

	// Check for optional F/P partial indicator
	if message.len >= 2 && (message[0] == `F` || message[0] == `P`) && message[1] == ` ` {
		message = message[2..]
	}

	return timestamp, stream, message
}

// matches_container_filter checks whether a container passes the configured
// include/exclude filters. A container matches if:
// 1. It is NOT in exclude_containers (by name or ID prefix)
// 2. If include_containers is set, it must be in that list
// 3. If include_images is set, its image must be in that list
// 4. If include_labels is set, it must have at least one of those labels
pub fn matches_container_filter(name string, image string, labels map[string]string, include_containers []string, exclude_containers []string, include_images []string, include_labels []string) bool {
	// Check exclusions first
	for ec in exclude_containers {
		if name == ec || name.starts_with(ec) {
			return false
		}
	}

	// Check container name inclusion
	if include_containers.len > 0 {
		mut found := false
		for ic in include_containers {
			if name == ic || name.starts_with(ic) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	// Check image inclusion
	if include_images.len > 0 {
		mut found := false
		for ii in include_images {
			if image == ii || image.starts_with(ii) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	// Check label inclusion
	if include_labels.len > 0 {
		mut found := false
		for il in include_labels {
			// Labels can be "key" or "key=value"
			parts := il.split('=')
			key := parts[0]
			if key in labels {
				if parts.len > 1 {
					// key=value match
					if labels[key] == parts[1] {
						found = true
						break
					}
				} else {
					// key-only match
					found = true
					break
				}
			}
		}
		if !found {
			return false
		}
	}

	return true
}

// build_container_metadata creates a metadata map from a DockerContainer.
pub fn build_container_metadata(container DockerContainer) map[string]string {
	mut meta := map[string]string{}

	meta['container_id'] = container.id

	if container.names.len > 0 {
		meta['container_name'] = container.names[0].trim_left('/')
	}

	meta['image'] = container.image
	meta['container_state'] = container.state
	meta['container_status'] = container.status

	for k, v in container.labels {
		meta['label.${k}'] = v
	}

	return meta
}
