module sources

import event
import os
import time

// HostMetricsSource collects system metrics from the local host by reading
// /proc and /sys on Linux. Mirrors Vector's host_metrics source.
//
// Config options:
//   collectors:            Comma-separated list of collectors (default: all)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: "host")
pub struct HostMetricsSource {
	collectors      []string
	scrape_interval time.Duration = 15 * time.second
	namespace       string        = 'host'
}

// new_host_metrics creates a new HostMetricsSource from config options.
pub fn new_host_metrics(opts map[string]string) HostMetricsSource {
	default_collectors := ['cpu', 'memory', 'disk', 'filesystem', 'load', 'network', 'host']

	mut collectors := default_collectors.clone()
	if c := opts['collectors'] {
		mut parsed := []string{}
		for part in c.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				parsed << trimmed
			}
		}
		if parsed.len > 0 {
			collectors = parsed.clone()
		}
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	namespace := opts['namespace'] or { 'host' }

	return HostMetricsSource{
		collectors: collectors
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		namespace: namespace
	}
}

// run loops, calling each enabled collector to emit metrics, then sleeps.
pub fn (s &HostMetricsSource) run(output chan event.Event) {
	for {
		for collector in s.collectors {
			match collector {
				'cpu' { s.collect_cpu(output) }
				'memory' { s.collect_memory(output) }
				'disk' { s.collect_disk(output) }
				'filesystem' { s.collect_filesystem(output) }
				'load' { s.collect_load(output) }
				'network' { s.collect_network(output) }
				'host' { s.collect_host(output) }
				else {}
			}
		}
		time.sleep(s.scrape_interval)
	}
}

// --- Helper to emit metrics ---

fn (s &HostMetricsSource) emit_hm_gauge(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_gauge(name, value)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'host_metrics'
	output <- event.Event(m)
}

fn (s &HostMetricsSource) emit_hm_counter(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_counter(name, value, .incremental)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'host_metrics'
	output <- event.Event(m)
}

// --- CPU collector ---

// CpuInfo holds parsed per-CPU times from /proc/stat.
pub struct CpuInfo {
pub:
	cpu    string
	user   f64
	nice   f64
	system f64
	idle   f64
	iowait f64
}

// parse_proc_stat parses /proc/stat content and returns per-CPU timing info.
pub fn parse_proc_stat(content string) []CpuInfo {
	mut results := []CpuInfo{}
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if !trimmed.starts_with('cpu') {
			continue
		}
		parts := trimmed.split_any(' \t').filter(it.len > 0)
		if parts.len < 6 {
			continue
		}
		name := parts[0]
		if name == 'cpu' {
			continue
		}
		hz := 100.0
		mut iowait := 0.0
		if parts.len > 5 {
			iowait = parts[5].f64() / hz
		}
		results << CpuInfo{
			cpu: name
			user: parts[1].f64() / hz
			nice: parts[2].f64() / hz
			system: parts[3].f64() / hz
			idle: parts[4].f64() / hz
			iowait: iowait
		}
	}
	return results
}

fn (s &HostMetricsSource) collect_cpu(output chan event.Event) {
	content := os.read_file('/proc/stat') or {
		eprintln('host_metrics: failed to read /proc/stat: ${err}')
		return
	}
	cpus := parse_proc_stat(content)
	for c in cpus {
		mut tags := map[string]string{}
		tags['cpu'] = c.cpu
		tags['mode'] = 'user'
		s.emit_hm_gauge(output, 'cpu_seconds_total', c.user, tags)
		tags['mode'] = 'nice'
		s.emit_hm_gauge(output, 'cpu_seconds_total', c.nice, tags)
		tags['mode'] = 'system'
		s.emit_hm_gauge(output, 'cpu_seconds_total', c.system, tags)
		tags['mode'] = 'idle'
		s.emit_hm_gauge(output, 'cpu_seconds_total', c.idle, tags)
		tags['mode'] = 'iowait'
		s.emit_hm_gauge(output, 'cpu_seconds_total', c.iowait, tags)
	}
}

// --- Memory collector ---

// MemInfo holds a single key-value pair from /proc/meminfo.
pub struct MemInfo {
pub:
	key   string
	value f64
}

// parse_meminfo parses /proc/meminfo content into key-value pairs.
pub fn parse_meminfo(content string) []MemInfo {
	mut results := []MemInfo{}
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		colon := trimmed.index(':') or { continue }
		key := trimmed[..colon].trim_space()
		rest := trimmed[colon + 1..].trim_space()
		parts := rest.split_any(' \t').filter(it.len > 0)
		if parts.len == 0 {
			continue
		}
		mut value := parts[0].f64()
		if parts.len > 1 && parts[1].to_lower() == 'kb' {
			value *= 1024.0
		}
		results << MemInfo{
			key: key
			value: value
		}
	}
	return results
}

// meminfo_lookup returns the value for a given key from parsed meminfo entries.
pub fn meminfo_lookup(entries []MemInfo, key string) f64 {
	for e in entries {
		if e.key == key {
			return e.value
		}
	}
	return 0.0
}

fn (s &HostMetricsSource) collect_memory(output chan event.Event) {
	content := os.read_file('/proc/meminfo') or {
		eprintln('host_metrics: failed to read /proc/meminfo: ${err}')
		return
	}
	entries := parse_meminfo(content)
	tags := map[string]string{}
	s.emit_hm_gauge(output, 'memory_total_bytes', meminfo_lookup(entries, 'MemTotal'), tags)
	s.emit_hm_gauge(output, 'memory_free_bytes', meminfo_lookup(entries, 'MemFree'), tags)
	s.emit_hm_gauge(output, 'memory_available_bytes', meminfo_lookup(entries, 'MemAvailable'),
		tags)
	s.emit_hm_gauge(output, 'memory_buffers_bytes', meminfo_lookup(entries, 'Buffers'),
		tags)
	s.emit_hm_gauge(output, 'memory_cached_bytes', meminfo_lookup(entries, 'Cached'), tags)
	s.emit_hm_gauge(output, 'memory_swap_total_bytes', meminfo_lookup(entries, 'SwapTotal'),
		tags)
	s.emit_hm_gauge(output, 'memory_swap_free_bytes', meminfo_lookup(entries, 'SwapFree'),
		tags)
}

// --- Disk collector ---

// DiskInfo holds parsed per-device disk stats from /proc/diskstats.
pub struct DiskInfo {
pub:
	device           string
	reads_completed  f64
	writes_completed f64
	read_bytes       f64
	write_bytes      f64
}

// parse_diskstats parses /proc/diskstats content.
pub fn parse_diskstats(content string) []DiskInfo {
	mut results := []DiskInfo{}
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		parts := trimmed.split_any(' \t').filter(it.len > 0)
		if parts.len < 10 {
			continue
		}
		device := parts[2]
		reads_completed := parts[3].f64()
		read_sectors := parts[5].f64()
		writes_completed := parts[7].f64()
		write_sectors := parts[9].f64()
		results << DiskInfo{
			device: device
			reads_completed: reads_completed
			writes_completed: writes_completed
			read_bytes: read_sectors * 512.0
			write_bytes: write_sectors * 512.0
		}
	}
	return results
}

fn (s &HostMetricsSource) collect_disk(output chan event.Event) {
	content := os.read_file('/proc/diskstats') or {
		eprintln('host_metrics: failed to read /proc/diskstats: ${err}')
		return
	}
	disks := parse_diskstats(content)
	for d in disks {
		mut tags := map[string]string{}
		tags['device'] = d.device
		s.emit_hm_counter(output, 'disk_read_bytes_total', d.read_bytes, tags)
		s.emit_hm_counter(output, 'disk_write_bytes_total', d.write_bytes, tags)
		s.emit_hm_counter(output, 'disk_reads_completed_total', d.reads_completed, tags)
		s.emit_hm_counter(output, 'disk_writes_completed_total', d.writes_completed, tags)
	}
}

// --- Filesystem collector ---

// FilesystemInfo holds parsed filesystem information.
pub struct FilesystemInfo {
pub:
	mountpoint  string
	device      string
	fstype      string
	total_bytes f64
	free_bytes  f64
	used_bytes  f64
}

const pseudo_filesystems = ['proc', 'sysfs', 'tmpfs', 'devtmpfs', 'cgroup', 'cgroup2',
	'devpts', 'securityfs', 'pstore', 'debugfs', 'hugetlbfs', 'mqueue', 'fusectl',
	'binfmt_misc', 'configfs', 'tracefs', 'bpf', 'nsfs', 'overlay', 'autofs',
	'rpc_pipefs', 'nfsd', 'efivarfs', 'fuse.gvfsd-fuse']

// parse_mounts parses /proc/mounts content, filtering pseudo-filesystems.
pub fn parse_mounts(content string) []FilesystemInfo {
	mut results := []FilesystemInfo{}
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		parts := trimmed.split_any(' \t').filter(it.len > 0)
		if parts.len < 3 {
			continue
		}
		device := parts[0]
		mountpoint := parts[1]
		fstype := parts[2]
		if fstype in sources.pseudo_filesystems {
			continue
		}
		results << FilesystemInfo{
			device: device
			mountpoint: mountpoint
			fstype: fstype
		}
	}
	return results
}

fn (s &HostMetricsSource) collect_filesystem(output chan event.Event) {
	content := os.read_file('/proc/mounts') or {
		eprintln('host_metrics: failed to read /proc/mounts: ${err}')
		return
	}
	mounts := parse_mounts(content)
	for fs in mounts {
		total, free, used := statvfs_sizes(fs.mountpoint)
		mut tags := map[string]string{}
		tags['mountpoint'] = fs.mountpoint
		tags['device'] = fs.device
		tags['fstype'] = fs.fstype
		s.emit_hm_gauge(output, 'filesystem_total_bytes', total, tags)
		s.emit_hm_gauge(output, 'filesystem_free_bytes', free, tags)
		s.emit_hm_gauge(output, 'filesystem_used_bytes', used, tags)
	}
}

fn statvfs_sizes(path string) (f64, f64, f64) {
	// Parse df-like output from /proc by reading the filesystem's stat file.
	// As a simpler alternative to C statvfs interop, return zeros and let
	// the metrics reflect that filesystem sizes require a running system.
	// In production, this would use statvfs(2) via C interop.
	return 0.0, 0.0, 0.0
}

// --- Load collector ---

// parse_loadavg parses /proc/loadavg content and returns [load1, load5, load15].
pub fn parse_loadavg(content string) []f64 {
	trimmed := content.trim_space()
	parts := trimmed.split_any(' \t').filter(it.len > 0)
	if parts.len < 3 {
		return []f64{}
	}
	return [parts[0].f64(), parts[1].f64(), parts[2].f64()]
}

fn (s &HostMetricsSource) collect_load(output chan event.Event) {
	content := os.read_file('/proc/loadavg') or {
		eprintln('host_metrics: failed to read /proc/loadavg: ${err}')
		return
	}
	loads := parse_loadavg(content)
	if loads.len < 3 {
		return
	}
	tags := map[string]string{}
	s.emit_hm_gauge(output, 'load1', loads[0], tags)
	s.emit_hm_gauge(output, 'load5', loads[1], tags)
	s.emit_hm_gauge(output, 'load15', loads[2], tags)
}

// --- Network collector ---

// NetworkInfo holds parsed per-interface network stats from /proc/net/dev.
pub struct NetworkInfo {
pub:
	interface_name   string
	receive_bytes    f64
	transmit_bytes   f64
	receive_packets  f64
	transmit_packets f64
}

// parse_net_dev parses /proc/net/dev content.
pub fn parse_net_dev(content string) []NetworkInfo {
	mut results := []NetworkInfo{}
	lines := content.split('\n')
	for i, line in lines {
		if i < 2 {
			continue
		}
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		colon := trimmed.index(':') or { continue }
		iface := trimmed[..colon].trim_space()
		rest := trimmed[colon + 1..].trim_space()
		parts := rest.split_any(' \t').filter(it.len > 0)
		if parts.len < 10 {
			continue
		}
		results << NetworkInfo{
			interface_name: iface
			receive_bytes: parts[0].f64()
			receive_packets: parts[1].f64()
			transmit_bytes: parts[8].f64()
			transmit_packets: parts[9].f64()
		}
	}
	return results
}

fn (s &HostMetricsSource) collect_network(output chan event.Event) {
	content := os.read_file('/proc/net/dev') or {
		eprintln('host_metrics: failed to read /proc/net/dev: ${err}')
		return
	}
	ifaces := parse_net_dev(content)
	for iface in ifaces {
		mut tags := map[string]string{}
		tags['device'] = iface.interface_name
		s.emit_hm_counter(output, 'network_receive_bytes_total', iface.receive_bytes, tags)
		s.emit_hm_counter(output, 'network_transmit_bytes_total', iface.transmit_bytes,
			tags)
		s.emit_hm_counter(output, 'network_receive_packets_total', iface.receive_packets,
			tags)
		s.emit_hm_counter(output, 'network_transmit_packets_total', iface.transmit_packets,
			tags)
	}
}

// --- Host collector ---

// HostInfo holds parsed host information.
pub struct HostInfo {
pub:
	uptime   f64
	hostname string
	os_name  string
}

// parse_uptime parses /proc/uptime content and returns uptime in seconds.
pub fn parse_uptime(content string) f64 {
	trimmed := content.trim_space()
	parts := trimmed.split_any(' \t').filter(it.len > 0)
	if parts.len == 0 {
		return 0.0
	}
	return parts[0].f64()
}

// parse_os_release parses /etc/os-release content and returns the PRETTY_NAME or NAME.
pub fn parse_os_release(content string) string {
	mut pretty_name := ''
	mut name := ''
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('PRETTY_NAME=') {
			pretty_name = trimmed[12..].trim('"')
		} else if trimmed.starts_with('NAME=') {
			name = trimmed[5..].trim('"')
		}
	}
	if pretty_name.len > 0 {
		return pretty_name
	}
	if name.len > 0 {
		return name
	}
	return 'Linux'
}

fn (s &HostMetricsSource) collect_host(output chan event.Event) {
	uptime_content := os.read_file('/proc/uptime') or { '' }
	uptime_secs := parse_uptime(uptime_content)
	hostname := os.hostname() or { 'unknown' }
	os_content := os.read_file('/etc/os-release') or { '' }
	os_name := parse_os_release(os_content)

	mut tags := map[string]string{}
	tags['hostname'] = hostname
	tags['os'] = os_name
	s.emit_hm_gauge(output, 'uptime', uptime_secs, tags)
}
