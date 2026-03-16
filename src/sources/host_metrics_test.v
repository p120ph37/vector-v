module sources

// --- Constructor tests ---

fn test_new_host_metrics_defaults() {
	s := new_host_metrics(map[string]string{})
	assert s.collectors == ['cpu', 'memory', 'disk', 'filesystem', 'load', 'network', 'host']
	assert s.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
	assert s.namespace == 'host'
}

fn test_new_host_metrics_custom_collectors() {
	s := new_host_metrics({
		'collectors': 'cpu,memory'
	})
	assert s.collectors == ['cpu', 'memory']
}

fn test_new_host_metrics_single_collector() {
	s := new_host_metrics({
		'collectors': 'load'
	})
	assert s.collectors == ['load']
}

fn test_new_host_metrics_collectors_with_spaces() {
	s := new_host_metrics({
		'collectors': ' cpu , memory , load '
	})
	assert s.collectors == ['cpu', 'memory', 'load']
}

fn test_new_host_metrics_empty_collectors_uses_default() {
	s := new_host_metrics({
		'collectors': '  ,  ,  '
	})
	// Empty after trimming: falls back to default
	assert s.collectors == ['cpu', 'memory', 'disk', 'filesystem', 'load', 'network', 'host']
}

fn test_new_host_metrics_custom_scrape_interval() {
	s := new_host_metrics({
		'scrape_interval_secs': '30'
	})
	assert s.scrape_interval == 30_000_000_000
}

fn test_new_host_metrics_negative_scrape_interval() {
	s := new_host_metrics({
		'scrape_interval_secs': '-5'
	})
	// Negative should default to 15 seconds
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_host_metrics_zero_scrape_interval() {
	s := new_host_metrics({
		'scrape_interval_secs': '0'
	})
	// Zero should default to 15 seconds
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_host_metrics_custom_namespace() {
	s := new_host_metrics({
		'namespace': 'myhost'
	})
	assert s.namespace == 'myhost'
}

fn test_new_host_metrics_all_options() {
	s := new_host_metrics({
		'collectors':           'cpu,load'
		'scrape_interval_secs': '60'
		'namespace':            'server'
	})
	assert s.collectors == ['cpu', 'load']
	assert s.scrape_interval == 60_000_000_000
	assert s.namespace == 'server'
}

fn test_new_host_metrics_fractional_scrape_interval() {
	s := new_host_metrics({
		'scrape_interval_secs': '0.5'
	})
	assert s.scrape_interval == 500_000_000 // 0.5 seconds
}

// --- parse_proc_stat tests ---

fn test_parse_proc_stat_basic() {
	content := 'cpu  1000 200 300 4000 50 60 70 0 0 0
cpu0 500 100 150 2000 25 30 35 0 0 0
cpu1 500 100 150 2000 25 30 35 0 0 0
'
	cpus := parse_proc_stat(content)
	assert cpus.len == 2
	assert cpus[0].cpu == 'cpu0'
	assert cpus[0].user == 5.0 // 500/100
	assert cpus[0].nice == 1.0 // 100/100
	assert cpus[0].system == 1.5 // 150/100
	assert cpus[0].idle == 20.0 // 2000/100
	assert cpus[0].iowait == 0.25 // 25/100
	assert cpus[1].cpu == 'cpu1'
}

fn test_parse_proc_stat_skips_aggregate() {
	content := 'cpu  1000 200 300 4000 50 60 70 0 0 0
'
	cpus := parse_proc_stat(content)
	assert cpus.len == 0
}

fn test_parse_proc_stat_empty() {
	cpus := parse_proc_stat('')
	assert cpus.len == 0
}

fn test_parse_proc_stat_non_cpu_lines() {
	content := 'cpu  1000 200 300 4000 50 60 70 0 0 0
cpu0 500 100 150 2000 25 30 35 0 0 0
intr 12345678 0 0 0 0 0 0
ctxt 98765432
btime 1234567890
processes 5000
procs_running 2
procs_blocked 0
'
	cpus := parse_proc_stat(content)
	assert cpus.len == 1
	assert cpus[0].cpu == 'cpu0'
}

fn test_parse_proc_stat_short_line() {
	content := 'cpu0 100 200
'
	cpus := parse_proc_stat(content)
	assert cpus.len == 0 // too few fields
}

fn test_parse_proc_stat_many_cpus() {
	mut lines := ['cpu  4000 800 600 16000 200 240 280 0 0 0']
	for i in 0 .. 8 {
		lines << 'cpu${i} 500 100 75 2000 25 30 35 0 0 0'
	}
	content := lines.join('\n')
	cpus := parse_proc_stat(content)
	assert cpus.len == 8
	for i in 0 .. 8 {
		assert cpus[i].cpu == 'cpu${i}'
	}
}

// --- parse_meminfo tests ---

fn test_parse_meminfo_basic() {
	content := 'MemTotal:       16384000 kB
MemFree:         8192000 kB
MemAvailable:   12000000 kB
Buffers:          512000 kB
Cached:          2048000 kB
SwapTotal:       4096000 kB
SwapFree:        4096000 kB
'
	entries := parse_meminfo(content)
	assert entries.len == 7

	assert meminfo_lookup(entries, 'MemTotal') == 16384000.0 * 1024.0
	assert meminfo_lookup(entries, 'MemFree') == 8192000.0 * 1024.0
	assert meminfo_lookup(entries, 'MemAvailable') == 12000000.0 * 1024.0
	assert meminfo_lookup(entries, 'Buffers') == 512000.0 * 1024.0
	assert meminfo_lookup(entries, 'Cached') == 2048000.0 * 1024.0
	assert meminfo_lookup(entries, 'SwapTotal') == 4096000.0 * 1024.0
	assert meminfo_lookup(entries, 'SwapFree') == 4096000.0 * 1024.0
}

fn test_parse_meminfo_empty() {
	entries := parse_meminfo('')
	assert entries.len == 0
}

fn test_parse_meminfo_no_unit() {
	content := 'HugePages_Total:       0
HugePages_Free:        0
'
	entries := parse_meminfo(content)
	assert entries.len == 2
	assert meminfo_lookup(entries, 'HugePages_Total') == 0.0
	assert meminfo_lookup(entries, 'HugePages_Free') == 0.0
}

fn test_parse_meminfo_missing_key() {
	content := 'MemTotal:       16384000 kB
'
	entries := parse_meminfo(content)
	assert meminfo_lookup(entries, 'NonExistent') == 0.0
}

fn test_parse_meminfo_full_format() {
	content := 'MemTotal:       32878564 kB
MemFree:          234832 kB
MemAvailable:   24563200 kB
Buffers:         1045360 kB
Cached:         22345632 kB
SwapCached:       102400 kB
Active:         15678900 kB
Inactive:       12345678 kB
SwapTotal:       8388604 kB
SwapFree:        8000000 kB
Dirty:             12456 kB
Writeback:             0 kB
AnonPages:       5678900 kB
Mapped:          1234567 kB
Shmem:            567890 kB
'
	entries := parse_meminfo(content)
	assert entries.len == 15
	assert meminfo_lookup(entries, 'MemTotal') == 32878564.0 * 1024.0
	assert meminfo_lookup(entries, 'SwapCached') == 102400.0 * 1024.0
}

// --- parse_diskstats tests ---

fn test_parse_diskstats_basic() {
	content := '   8       0 sda 100 50 2048 500 200 100 4096 300 0 400 800
   8       1 sda1 80 40 1024 400 150 80 2048 200 0 300 600
'
	disks := parse_diskstats(content)
	assert disks.len == 2
	assert disks[0].device == 'sda'
	assert disks[0].reads_completed == 100.0
	assert disks[0].read_bytes == 2048.0 * 512.0
	assert disks[0].writes_completed == 200.0
	assert disks[0].write_bytes == 4096.0 * 512.0
	assert disks[1].device == 'sda1'
}

fn test_parse_diskstats_empty() {
	disks := parse_diskstats('')
	assert disks.len == 0
}

fn test_parse_diskstats_short_line() {
	content := '   8       0 sda 100 50
'
	disks := parse_diskstats(content)
	assert disks.len == 0 // too few fields
}

fn test_parse_diskstats_multiple_devices() {
	content := '   8       0 sda 1000 500 20480 5000 2000 1000 40960 3000 0 4000 8000
   8      16 sdb 500 250 10240 2500 1000 500 20480 1500 0 2000 4000
 253       0 dm-0 800 0 16384 4000 1500 0 30720 2500 0 3000 6500
'
	disks := parse_diskstats(content)
	assert disks.len == 3
	assert disks[0].device == 'sda'
	assert disks[1].device == 'sdb'
	assert disks[2].device == 'dm-0'
}

fn test_parse_diskstats_zero_values() {
	content := '   8       0 loop0 0 0 0 0 0 0 0 0 0 0 0
'
	disks := parse_diskstats(content)
	assert disks.len == 1
	assert disks[0].device == 'loop0'
	assert disks[0].reads_completed == 0.0
	assert disks[0].read_bytes == 0.0
	assert disks[0].writes_completed == 0.0
	assert disks[0].write_bytes == 0.0
}

// --- parse_mounts tests ---

fn test_parse_mounts_basic() {
	content := '/dev/sda1 / ext4 rw,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
tmpfs /tmp tmpfs rw,nosuid,nodev 0 0
/dev/sda2 /home ext4 rw,relatime 0 0
'
	mounts := parse_mounts(content)
	// Should skip proc, sysfs, tmpfs
	assert mounts.len == 2
	assert mounts[0].mountpoint == '/'
	assert mounts[0].device == '/dev/sda1'
	assert mounts[0].fstype == 'ext4'
	assert mounts[1].mountpoint == '/home'
}

fn test_parse_mounts_empty() {
	mounts := parse_mounts('')
	assert mounts.len == 0
}

fn test_parse_mounts_all_pseudo() {
	content := 'proc /proc proc rw 0 0
sysfs /sys sysfs rw 0 0
devtmpfs /dev devtmpfs rw 0 0
tmpfs /run tmpfs rw 0 0
cgroup2 /sys/fs/cgroup cgroup2 rw 0 0
'
	mounts := parse_mounts(content)
	assert mounts.len == 0
}

fn test_parse_mounts_various_real_fs() {
	content := '/dev/sda1 / ext4 rw 0 0
/dev/sdb1 /data xfs rw 0 0
/dev/nvme0n1p1 /boot vfat rw 0 0
//server/share /mnt/smb cifs rw 0 0
'
	mounts := parse_mounts(content)
	assert mounts.len == 4
	assert mounts[0].fstype == 'ext4'
	assert mounts[1].fstype == 'xfs'
	assert mounts[2].fstype == 'vfat'
	assert mounts[3].fstype == 'cifs'
}

fn test_parse_mounts_devpts_filtered() {
	content := 'devpts /dev/pts devpts rw 0 0
'
	mounts := parse_mounts(content)
	assert mounts.len == 0
}

fn test_parse_mounts_short_line() {
	content := '/dev/sda1 /
'
	mounts := parse_mounts(content)
	assert mounts.len == 0 // too few fields
}

// --- parse_loadavg tests ---

fn test_parse_loadavg_basic() {
	content := '0.50 0.75 1.00 2/500 12345'
	loads := parse_loadavg(content)
	assert loads.len == 3
	assert loads[0] == 0.50
	assert loads[1] == 0.75
	assert loads[2] == 1.00
}

fn test_parse_loadavg_empty() {
	loads := parse_loadavg('')
	assert loads.len == 0
}

fn test_parse_loadavg_high_values() {
	content := '12.50 8.75 6.25 10/1000 99999'
	loads := parse_loadavg(content)
	assert loads.len == 3
	assert loads[0] == 12.50
	assert loads[1] == 8.75
	assert loads[2] == 6.25
}

fn test_parse_loadavg_zero_values() {
	content := '0.00 0.00 0.00 1/100 1'
	loads := parse_loadavg(content)
	assert loads.len == 3
	assert loads[0] == 0.0
	assert loads[1] == 0.0
	assert loads[2] == 0.0
}

fn test_parse_loadavg_short() {
	content := '0.50 0.75'
	loads := parse_loadavg(content)
	assert loads.len == 0 // too few fields
}

fn test_parse_loadavg_with_trailing_newline() {
	content := '1.23 4.56 7.89 3/200 54321\n'
	loads := parse_loadavg(content)
	assert loads.len == 3
	assert loads[0] == 1.23
	assert loads[1] == 4.56
	assert loads[2] == 7.89
}

// --- parse_net_dev tests ---

fn test_parse_net_dev_basic() {
	content := 'Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 1000000   5000    0    0    0     0          0         0  2000000  3000    0    0    0     0       0          0
    lo:  500000   1000    0    0    0     0          0         0   500000  1000    0    0    0     0       0          0
'
	ifaces := parse_net_dev(content)
	assert ifaces.len == 2
	assert ifaces[0].interface_name == 'eth0'
	assert ifaces[0].receive_bytes == 1000000.0
	assert ifaces[0].receive_packets == 5000.0
	assert ifaces[0].transmit_bytes == 2000000.0
	assert ifaces[0].transmit_packets == 3000.0
	assert ifaces[1].interface_name == 'lo'
	assert ifaces[1].receive_bytes == 500000.0
	assert ifaces[1].transmit_bytes == 500000.0
}

fn test_parse_net_dev_empty() {
	ifaces := parse_net_dev('')
	assert ifaces.len == 0
}

fn test_parse_net_dev_headers_only() {
	content := 'Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
'
	ifaces := parse_net_dev(content)
	assert ifaces.len == 0
}

fn test_parse_net_dev_multiple_interfaces() {
	content := 'Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 1000 100 0 0 0 0 0 0 2000 200 0 0 0 0 0 0
  eth1: 3000 300 0 0 0 0 0 0 4000 400 0 0 0 0 0 0
 wlan0: 5000 500 0 0 0 0 0 0 6000 600 0 0 0 0 0 0
    lo: 7000 700 0 0 0 0 0 0 7000 700 0 0 0 0 0 0
'
	ifaces := parse_net_dev(content)
	assert ifaces.len == 4
	assert ifaces[0].interface_name == 'eth0'
	assert ifaces[1].interface_name == 'eth1'
	assert ifaces[2].interface_name == 'wlan0'
	assert ifaces[3].interface_name == 'lo'
}

fn test_parse_net_dev_large_values() {
	content := 'Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0: 98765432100 87654321 0 0 0 0 0 0 12345678900 11223344 0 0 0 0 0 0
'
	ifaces := parse_net_dev(content)
	assert ifaces.len == 1
	assert ifaces[0].receive_bytes == 98765432100.0
	assert ifaces[0].transmit_bytes == 12345678900.0
}

fn test_parse_net_dev_no_colon() {
	content := 'Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  eth0 1000 100 0 0 0 0 0 0 2000 200 0 0 0 0 0 0
'
	ifaces := parse_net_dev(content)
	// no colon means the line is skipped
	assert ifaces.len == 0
}

// --- parse_uptime tests ---

fn test_parse_uptime_basic() {
	content := '12345.67 23456.78'
	uptime := parse_uptime(content)
	assert uptime == 12345.67
}

fn test_parse_uptime_empty() {
	uptime := parse_uptime('')
	assert uptime == 0.0
}

fn test_parse_uptime_with_newline() {
	content := '99999.99 88888.88\n'
	uptime := parse_uptime(content)
	assert uptime == 99999.99
}

fn test_parse_uptime_small() {
	content := '0.50 0.25'
	uptime := parse_uptime(content)
	assert uptime == 0.50
}

// --- parse_os_release tests ---

fn test_parse_os_release_pretty_name() {
	content := 'NAME="Ubuntu"
VERSION="22.04 LTS (Jammy Jellyfish)"
PRETTY_NAME="Ubuntu 22.04 LTS"
ID=ubuntu
'
	os_name := parse_os_release(content)
	assert os_name == 'Ubuntu 22.04 LTS'
}

fn test_parse_os_release_no_pretty_name() {
	content := 'NAME="Arch Linux"
ID=arch
'
	os_name := parse_os_release(content)
	assert os_name == 'Arch Linux'
}

fn test_parse_os_release_empty() {
	os_name := parse_os_release('')
	assert os_name == 'Linux'
}

fn test_parse_os_release_prefers_pretty_name() {
	content := 'NAME="Debian"
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
'
	os_name := parse_os_release(content)
	assert os_name == 'Debian GNU/Linux 12 (bookworm)'
}

fn test_parse_os_release_no_quotes() {
	content := 'NAME=Alpine
PRETTY_NAME=Alpine Linux
'
	os_name := parse_os_release(content)
	assert os_name == 'Alpine Linux'
}

// --- meminfo_lookup tests ---

fn test_meminfo_lookup_found() {
	entries := [
		MemInfo{key: 'MemTotal', value: 1024.0},
		MemInfo{key: 'MemFree', value: 512.0},
	]
	assert meminfo_lookup(entries, 'MemTotal') == 1024.0
	assert meminfo_lookup(entries, 'MemFree') == 512.0
}

fn test_meminfo_lookup_not_found() {
	entries := [
		MemInfo{key: 'MemTotal', value: 1024.0},
	]
	assert meminfo_lookup(entries, 'Missing') == 0.0
}

fn test_meminfo_lookup_empty() {
	entries := []MemInfo{}
	assert meminfo_lookup(entries, 'MemTotal') == 0.0
}
