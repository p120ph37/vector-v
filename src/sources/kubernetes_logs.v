module sources

import event
import json
import net.http
import os
import time

// KubernetesLogsSource reads pod log files from the local node filesystem and
// enriches them with Kubernetes metadata. Mirrors Vector's kubernetes_logs source.
//
// Pod log files follow the path format:
//   /var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/<restart-count>.log
//
// Log lines use CRI (Container Runtime Interface) format:
//   <timestamp> <stream> <flag> <message>
//
// Config options:
//   self_node_name:    Node name for filtering (default: from VECTOR_SELF_NODE_NAME or NODE_NAME env)
//   data_dir:          Directory containing pod logs (default: /var/log/pods)
//   glob_pattern:      Glob pattern for log files (default: **/*.log)
//   max_line_bytes:    Max line length (default: 32768)
//   max_read_bytes:    Max bytes per read (default: 2048)
//   glob_cooldown_ms:  File discovery interval in ms (default: 5000)
//   read_from:         Where to start reading: "beginning" or "end" (default: "beginning")
//   ignore_older_secs: Ignore files older than this many seconds (default: 0 = disabled)
//   namespace_labels:  Insert pod_namespace field (default: true)
//   pod_annotations:   Insert pod annotations (default: true)
//   kube_api_url:      Kubernetes API URL (default: https://kubernetes.default.svc)
//   kube_token_path:   Path to service account token (default: /var/run/secrets/kubernetes.io/serviceaccount/token)
//   kube_ca_path:      Path to CA cert (default: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
pub struct KubernetesLogsSource {
	self_node_name   string
	data_dir         string = '/var/log/pods'
	glob_pattern     string = '**/*.log'
	exclude_paths    []string
	max_line_bytes   int    = 32768
	max_read_bytes   int    = 2048
	glob_cooldown_ms int    = 5000
	read_from        string = 'beginning' // or 'end'
	ignore_older_secs int // 0 = disabled
	namespace_labels bool   = true
	pod_annotations  bool   = true
	kube_api_url     string = 'https://kubernetes.default.svc'
	kube_token_path  string = '/var/run/secrets/kubernetes.io/serviceaccount/token'
	kube_ca_path     string = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
}

// new_kubernetes_logs creates a new KubernetesLogsSource from config options.
pub fn new_kubernetes_logs(opts map[string]string) KubernetesLogsSource {
	// Resolve self_node_name: config > VECTOR_SELF_NODE_NAME > NODE_NAME
	mut node_name := ''
	if n := opts['self_node_name'] {
		node_name = n
	} else {
		node_name = os.getenv('VECTOR_SELF_NODE_NAME')
		if node_name.len == 0 {
			node_name = os.getenv('NODE_NAME')
		}
	}

	mut data_dir := '/var/log/pods'
	if d := opts['data_dir'] {
		if d.len > 0 {
			data_dir = d
		}
	}

	mut glob_pattern := '**/*.log'
	if g := opts['glob_pattern'] {
		if g.len > 0 {
			glob_pattern = g
		}
	}

	mut exclude_paths := []string{}
	if ep := opts['exclude_paths'] {
		for part in ep.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				exclude_paths << trimmed
			}
		}
	}

	mut max_line_bytes := 32768
	if ml := opts['max_line_bytes'] {
		max_line_bytes = ml.int()
		if max_line_bytes <= 0 {
			max_line_bytes = 32768
		}
	}

	mut max_read_bytes := 2048
	if mr := opts['max_read_bytes'] {
		max_read_bytes = mr.int()
		if max_read_bytes <= 0 {
			max_read_bytes = 2048
		}
	}

	mut glob_cooldown_ms := 5000
	if gc := opts['glob_cooldown_ms'] {
		glob_cooldown_ms = gc.int()
		if glob_cooldown_ms <= 0 {
			glob_cooldown_ms = 5000
		}
	}

	mut read_from := 'beginning'
	if rf := opts['read_from'] {
		if rf == 'end' {
			read_from = 'end'
		}
	}

	mut ignore_older_secs := 0
	if io := opts['ignore_older_secs'] {
		ignore_older_secs = io.int()
		if ignore_older_secs < 0 {
			ignore_older_secs = 0
		}
	}

	mut namespace_labels := true
	if nl := opts['namespace_labels'] {
		namespace_labels = nl != 'false'
	}

	mut pod_annotations_val := true
	if pa := opts['pod_annotations'] {
		pod_annotations_val = pa != 'false'
	}

	mut kube_api_url := 'https://kubernetes.default.svc'
	if ku := opts['kube_api_url'] {
		if ku.len > 0 {
			kube_api_url = ku
		}
	}

	mut kube_token_path := '/var/run/secrets/kubernetes.io/serviceaccount/token'
	if tp := opts['kube_token_path'] {
		if tp.len > 0 {
			kube_token_path = tp
		}
	}

	mut kube_ca_path := '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
	if cp := opts['kube_ca_path'] {
		if cp.len > 0 {
			kube_ca_path = cp
		}
	}

	return KubernetesLogsSource{
		self_node_name: node_name
		data_dir: data_dir
		glob_pattern: glob_pattern
		exclude_paths: exclude_paths
		max_line_bytes: max_line_bytes
		max_read_bytes: max_read_bytes
		glob_cooldown_ms: glob_cooldown_ms
		read_from: read_from
		ignore_older_secs: ignore_older_secs
		namespace_labels: namespace_labels
		pod_annotations: pod_annotations_val
		kube_api_url: kube_api_url
		kube_token_path: kube_token_path
		kube_ca_path: kube_ca_path
	}
}

// parse_pod_log_path extracts namespace, pod_name, and container_name from a
// Kubernetes pod log path of the form:
//   /var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/<restart-count>.log
// Returns (namespace, pod_name, container_name) or none if the path is invalid.
pub fn parse_pod_log_path(path string) ?(string, string, string) {
	// Normalize path separators
	normalized := path.replace('\\', '/')
	parts := normalized.split('/')

	// Need at least: .../<ns_pod_uid>/<container>/<N>.log
	if parts.len < 3 {
		return none
	}

	// The log file is at parts[len-1], container at parts[len-2], pod dir at parts[len-3]
	container_name := parts[parts.len - 2]
	pod_dir := parts[parts.len - 3]

	if container_name.len == 0 || pod_dir.len == 0 {
		return none
	}

	// pod_dir format: <namespace>_<pod-name>_<pod-uid>
	// Split by underscore - namespace is first, uid is last, pod name is everything in between
	underscore_parts := pod_dir.split('_')
	if underscore_parts.len < 3 {
		return none
	}

	namespace := underscore_parts[0]
	// Pod UID is the last part
	// Pod name is everything between namespace and uid
	pod_name := underscore_parts[1..underscore_parts.len - 1].join('_')

	if namespace.len == 0 || pod_name.len == 0 {
		return none
	}

	return namespace, pod_name, container_name
}

// parse_kubernetes_log_line parses a CRI log format line:
//   <timestamp> <stream> <flag> <message>
// Returns (timestamp, stream, message) or none if the line is invalid.
// The flag is consumed internally: "F" = full line, "P" = partial line.
pub fn parse_kubernetes_log_line(line string) ?(string, string, string) {
	if line.len == 0 {
		return none
	}

	// Find first space (after timestamp)
	first_space := line.index(' ') or { return none }
	if first_space == 0 || first_space >= line.len - 1 {
		return none
	}
	timestamp := line[..first_space]

	rest1 := line[first_space + 1..]

	// Find second space (after stream)
	second_space := rest1.index(' ') or { return none }
	if second_space == 0 || second_space >= rest1.len - 1 {
		return none
	}
	stream := rest1[..second_space]

	rest2 := rest1[second_space + 1..]

	// Find third space (after flag)
	third_space := rest2.index(' ') or {
		// Flag only, no message (edge case: empty message after flag)
		if rest2 == 'F' || rest2 == 'P' {
			return timestamp, stream, ''
		}
		return none
	}
	flag := rest2[..third_space]

	if flag != 'F' && flag != 'P' {
		return none
	}

	message := rest2[third_space + 1..]
	return timestamp, stream, message
}

// is_partial_line checks if a CRI log line has the "P" (partial) flag.
pub fn is_partial_line(line string) bool {
	if line.len == 0 {
		return false
	}

	// Find first space (after timestamp)
	first_space := line.index(' ') or { return false }
	if first_space >= line.len - 1 {
		return false
	}
	rest1 := line[first_space + 1..]

	// Find second space (after stream)
	second_space := rest1.index(' ') or { return false }
	if second_space >= rest1.len - 1 {
		return false
	}
	rest2 := rest1[second_space + 1..]

	// Check if flag is 'P'
	return rest2.starts_with('P ')  || rest2 == 'P'
}

// merge_partial_lines merges a sequence of CRI partial log lines into a single
// message. Each line's message portion is extracted and concatenated.
pub fn merge_partial_lines(lines []string) string {
	if lines.len == 0 {
		return ''
	}
	if lines.len == 1 {
		_, _, msg := parse_kubernetes_log_line(lines[0]) or { return lines[0] }
		return msg
	}

	mut parts := []string{cap: lines.len}
	for line in lines {
		_, _, msg := parse_kubernetes_log_line(line) or { continue }
		parts << msg
	}
	return parts.join('')
}

// run is the main loop: discovers log files, reads new lines, and emits events.
pub fn (s &KubernetesLogsSource) run(output chan event.Event) {
	mut file_offsets := map[string]i64{}
	mut partial_buf := map[string][]string{}

	for {
		// Discover log files
		files := s.discover_files()

		for file_path in files {
			// Parse metadata from path
			namespace, pod_name, container_name := parse_pod_log_path(file_path) or {
				continue
			}

			// Check ignore_older_secs
			if s.ignore_older_secs > 0 {
				stat := os.stat(file_path) or { continue }
				age_secs := time.now().unix() - i64(stat.mtime)
				if age_secs > i64(s.ignore_older_secs) {
					continue
				}
			}

			// Initialize offset for new files
			if file_path !in file_offsets {
				if s.read_from == 'end' {
					file_offsets[file_path] = os.file_size(file_path)
				} else {
					file_offsets[file_path] = 0
				}
			}

			// Read new data
			current_offset := file_offsets[file_path]
			file_size := os.file_size(file_path)
			if file_size <= current_offset {
				continue
			}

			mut f := os.open(file_path) or { continue }
			f.seek(current_offset, .start) or {
				f.close()
				continue
			}

			mut bytes_read := i64(0)
			mut buf := []u8{len: s.max_read_bytes}
			n := f.read(mut buf) or {
				f.close()
				continue
			}
			f.close()

			if n == 0 {
				continue
			}

			bytes_read = i64(n)
			data := buf[..n].bytestr()

			// Split into lines
			raw_lines := data.split('\n')
			mut lines := []string{}
			for raw_line in raw_lines {
				trimmed := raw_line.trim_right('\r')
				if trimmed.len > 0 {
					if trimmed.len > s.max_line_bytes {
						lines << trimmed[..s.max_line_bytes]
					} else {
						lines << trimmed
					}
				}
			}

			// If the data doesn't end with newline, the last line may be incomplete
			// so don't advance past it
			mut adjust := i64(0)
			if data.len > 0 && !data.ends_with('\n') && raw_lines.len > 0 {
				last := raw_lines[raw_lines.len - 1]
				adjust = i64(last.len)
				if lines.len > 0 {
					lines = lines[..lines.len - 1].clone()
				}
			}

			file_offsets[file_path] = current_offset + bytes_read - adjust

			// Process lines
			for line in lines {
				if is_partial_line(line) {
					// Buffer partial lines
					if file_path !in partial_buf {
						partial_buf[file_path] = []string{}
					}
					partial_buf[file_path] << line
					continue
				}

				// Full line - check if we have buffered partials
				mut message := ''
				mut ts := ''
				mut stream := ''

				if file_path in partial_buf && partial_buf[file_path].len > 0 {
					partial_buf[file_path] << line
					message = merge_partial_lines(partial_buf[file_path])
					// Use timestamp/stream from the first partial
					ts, stream, _ = parse_kubernetes_log_line(partial_buf[file_path][0]) or {
						'', '', ''
					}
					partial_buf[file_path] = []string{}
				} else {
					ts, stream, message = parse_kubernetes_log_line(line) or {
						// If not CRI format, emit raw line
						mut ev := event.new_log(line)
						ev.meta.source_type = 'kubernetes_logs'
						if s.namespace_labels {
							ev.set('kubernetes.pod_namespace', event.Value(namespace))
						}
						ev.set('kubernetes.pod_name', event.Value(pod_name))
						ev.set('kubernetes.container_name', event.Value(container_name))
						output <- event.Event(ev)
						continue
					}
				}

				mut ev := event.new_log(message)
				ev.meta.source_type = 'kubernetes_logs'
				if s.namespace_labels {
					ev.set('kubernetes.pod_namespace', event.Value(namespace))
				}
				ev.set('kubernetes.pod_name', event.Value(pod_name))
				ev.set('kubernetes.container_name', event.Value(container_name))
				ev.set('stream', event.Value(stream))
				ev.set('timestamp', event.Value(ts))
				output <- event.Event(ev)
			}
		}

		time.sleep(time.Duration(i64(s.glob_cooldown_ms) * 1_000_000))
	}
}

// discover_files finds all log files matching the glob pattern in data_dir.
fn (s &KubernetesLogsSource) discover_files() []string {
	pattern := os.join_path(s.data_dir, s.glob_pattern)
	matches := os.glob(pattern) or { return []string{} }

	if s.exclude_paths.len == 0 {
		return matches
	}

	mut result := []string{cap: matches.len}
	for m in matches {
		mut excluded := false
		for ep in s.exclude_paths {
			if m.contains(ep) {
				excluded = true
				break
			}
		}
		if !excluded {
			result << m
		}
	}
	return result
}

// KubePodMetadata is a minimal struct for decoding Kubernetes pod API responses.
struct KubePodMetadata {
	metadata KubePodMeta
}

struct KubePodMeta {
	name        string
	namespace   string
	labels      map[string]string
	annotations map[string]string
}

// fetch_pod_metadata calls the Kubernetes API to retrieve pod metadata.
// Returns a map of annotation key-value pairs, or an empty map on failure.
fn (s &KubernetesLogsSource) fetch_pod_metadata(namespace string, pod_name string) map[string]string {
	token := os.read_file(s.kube_token_path) or { return map[string]string{} }
	url := '${s.kube_api_url}/api/v1/namespaces/${namespace}/pods/${pod_name}'

	mut header := http.Header{}
	header.add(.authorization, 'Bearer ${token.trim_space()}')
	resp := http.fetch(http.FetchConfig{
		url: url
		method: .get
		header: header
		validate: false
	}) or {
		return map[string]string{}
	}

	if resp.status_code != 200 {
		return map[string]string{}
	}

	pod := json.decode(KubePodMetadata, resp.body) or { return map[string]string{} }
	return pod.metadata.annotations.clone()
}
