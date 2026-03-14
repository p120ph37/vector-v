module vrl

import crypto.sha1
import encoding.base64

// community_id — generates a Community ID flow hash per
// https://github.com/corelight/community-id-spec
//
// community_id(source_ip, destination_ip, protocol, [source_port], [destination_port], [seed])
fn fn_community_id(args []VrlValue, named map[string]VrlValue) !VrlValue {
	src_ip_str := get_named_or_pos_string(args, named, 'source_ip', 0) or {
		return error('community_id requires source_ip')
	}
	dst_ip_str := get_named_or_pos_string(args, named, 'destination_ip', 1) or {
		return error('community_id requires destination_ip')
	}
	protocol_val := get_named_or_pos_int(args, named, 'protocol', 2) or {
		return error('community_id requires protocol')
	}
	if protocol_val < 0 || protocol_val > 255 {
		return error('protocol must be between 0 and 255')
	}
	protocol := u8(protocol_val)

	src_port_opt := get_named_or_pos_int_opt(args, named, 'source_port', 3)
	dst_port_opt := get_named_or_pos_int_opt(args, named, 'destination_port', 4)
	seed_val := get_named_or_pos_int(args, named, 'seed', 5) or { i64(0) }
	if seed_val < 0 || seed_val > 65535 {
		return error('seed must be between 0 and 65535')
	}
	seed := u16(seed_val)

	// Validate ports for protocols that require them
	is_port_protocol := protocol == 6 || protocol == 17 || protocol == 132 // TCP, UDP, SCTP
	if is_port_protocol {
		if src_port_opt == none || dst_port_opt == none {
			return error('src port and dst port should be set when protocol is tcp/udp/sctp')
		}
	}

	mut src_port := u16(0)
	mut dst_port := u16(0)
	mut has_ports := false
	if sp := src_port_opt {
		if sp < 0 || sp > 65535 {
			return error('source port must be between 0 and 65535')
		}
		src_port = u16(sp)
		has_ports = true
	}
	if dp := dst_port_opt {
		if dp < 0 || dp > 65535 {
			return error('destination port must be between 0 and 65535')
		}
		dst_port = u16(dp)
		has_ports = true
	}

	// Parse IPs
	src_ip := parse_ip_for_cid(src_ip_str) or {
		return error('unable to parse source IP address: ${err}')
	}
	dst_ip := parse_ip_for_cid(dst_ip_str) or {
		return error('unable to parse destination IP address: ${err}')
	}

	// Determine ordering — Community ID is bidirectional
	is_one_way := protocol == 1 || protocol == 58 // ICMP, ICMPv6
	mut ordered_src_ip := src_ip.clone()
	mut ordered_dst_ip := dst_ip.clone()
	mut ordered_src_port := src_port
	mut ordered_dst_port := dst_port

	if !is_one_way {
		if cid_ip_less(src_ip, dst_ip) || (cid_ip_eq(src_ip, dst_ip) && src_port < dst_port) {
			// already in order
		} else if cid_ip_eq(src_ip, dst_ip) && src_port == dst_port {
			// equal, keep as is
		} else {
			ordered_src_ip = dst_ip.clone()
			ordered_dst_ip = src_ip.clone()
			ordered_src_port = dst_port
			ordered_dst_port = src_port
		}
	} else {
		// ICMP: use type/code mapping for ordering
		mapped_src := icmp_port_map(src_port, protocol == 58)
		mapped_dst := icmp_port_map(dst_port, protocol == 58)
		if cid_ip_less(src_ip, dst_ip) {
			ordered_src_port = src_port
			ordered_dst_port = mapped_src
		} else if cid_ip_less(dst_ip, src_ip) {
			ordered_src_ip = dst_ip.clone()
			ordered_dst_ip = src_ip.clone()
			ordered_src_port = dst_port
			ordered_dst_port = mapped_dst
		} else {
			if src_port < dst_port {
				// keep as is
			} else {
				ordered_src_ip = dst_ip.clone()
				ordered_dst_ip = src_ip.clone()
				ordered_src_port = dst_port
				ordered_dst_port = mapped_dst
			}
		}
	}

	// Build the hash input
	mut buf := []u8{cap: 64}
	// Seed (2 bytes, network byte order)
	buf << u8(seed >> 8)
	buf << u8(seed & 0xFF)
	// Source IP
	for b in ordered_src_ip {
		buf << b
	}
	// Destination IP
	for b in ordered_dst_ip {
		buf << b
	}
	// Protocol
	buf << protocol
	// Padding
	buf << u8(0)

	if has_ports || is_port_protocol {
		// Source port (2 bytes, network byte order)
		buf << u8(ordered_src_port >> 8)
		buf << u8(ordered_src_port & 0xFF)
		// Destination port (2 bytes, network byte order)
		buf << u8(ordered_dst_port >> 8)
		buf << u8(ordered_dst_port & 0xFF)
	}

	// SHA1 hash
	digest := sha1.sum(buf)
	b64 := base64.encode(digest)
	return VrlValue('1:${b64}')
}

struct CidIp {
	bytes []u8
}

fn parse_ip_for_cid(s string) ![]u8 {
	if s.contains(':') {
		return ipv6_to_bytes(s)
	}
	parts := s.split('.')
	if parts.len != 4 {
		return error('invalid IP address')
	}
	mut result := []u8{cap: 4}
	for p in parts {
		for c in p.bytes() {
			if !c.is_digit() {
				return error('invalid IP address')
			}
		}
		v := p.int()
		if v < 0 || v > 255 {
			return error('invalid octet')
		}
		result << u8(v)
	}
	return result
}

fn cid_ip_less(a []u8, b []u8) bool {
	min := if a.len < b.len { a.len } else { b.len }
	// If different lengths, shorter (IPv4) comes first
	if a.len != b.len {
		return a.len < b.len
	}
	for i in 0 .. min {
		if a[i] < b[i] {
			return true
		}
		if a[i] > b[i] {
			return false
		}
	}
	return false
}

fn cid_ip_eq(a []u8, b []u8) bool {
	if a.len != b.len {
		return false
	}
	for i in 0 .. a.len {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// icmp_port_map maps ICMP types to their paired type for bidirectional matching.
fn icmp_port_map(typ u16, is_v6 bool) u16 {
	if is_v6 {
		return match typ {
			128 { u16(129) } // Echo Request -> Echo Reply
			129 { u16(128) }
			130 { u16(131) } // Multicast Listener Query -> Report
			131 { u16(130) }
			132 { u16(132) }
			133 { u16(136) } // Router Solicitation -> Advertisement
			134 { u16(133) }
			135 { u16(136) } // Neighbor Solicitation -> Advertisement
			136 { u16(135) }
			137 { u16(137) }
			139 { u16(140) } // Node Information Query -> Response
			140 { u16(139) }
			141 { u16(142) } // Inverse Neighbor Discovery Solicitation -> Advertisement
			142 { u16(141) }
			143 { u16(143) }
			144 { u16(145) } // Home Agent Address Discovery Request -> Reply
			145 { u16(144) }
			else { typ }
		}
	}
	return match typ {
		0 { u16(8) } // Echo Reply -> Echo Request
		8 { u16(0) }
		13 { u16(14) } // Timestamp -> Timestamp Reply
		14 { u16(13) }
		15 { u16(16) } // Information Request -> Reply
		16 { u16(15) }
		17 { u16(18) } // Address Mask Request -> Reply
		18 { u16(17) }
		else { typ }
	}
}

// Helper: get a string from named args or positional args.
fn get_named_or_pos_string(args []VrlValue, named map[string]VrlValue, key string, pos int) !string {
	if v := named[key] {
		s := v
		match s {
			string { return s }
			else { return error('expected string for ${key}') }
		}
	}
	if pos < args.len {
		a := args[pos]
		match a {
			string { return a }
			else { return error('expected string for ${key}') }
		}
	}
	return error('missing argument: ${key}')
}

fn get_named_or_pos_int(args []VrlValue, named map[string]VrlValue, key string, pos int) !i64 {
	if v := named[key] {
		i := v
		match i {
			i64 { return i }
			else { return error('expected integer for ${key}') }
		}
	}
	if pos < args.len {
		a := args[pos]
		match a {
			i64 { return a }
			else { return error('expected integer for ${key}') }
		}
	}
	return error('missing argument: ${key}')
}

fn get_named_or_pos_int_opt(args []VrlValue, named map[string]VrlValue, key string, pos int) ?i64 {
	if v := named[key] {
		i := v
		match i {
			i64 { return i }
			else { return none }
		}
	}
	if pos < args.len {
		a := args[pos]
		match a {
			i64 { return a }
			VrlNull { return none }
			else { return none }
		}
	}
	return none
}
