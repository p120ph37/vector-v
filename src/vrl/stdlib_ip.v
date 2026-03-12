module vrl

// ip_aton(value) - convert IPv4 to integer
fn fn_ip_aton(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_aton requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ip_aton requires a string') }
	}
	parts := s.split('.')
	if parts.len != 4 {
		return error('invalid IPv4 address: ${s}')
	}
	mut result := i64(0)
	for p in parts {
		octet := p.int()
		if octet < 0 || octet > 255 {
			return error('invalid IPv4 octet: ${p}')
		}
		result = result * 256 + octet
	}
	return VrlValue(int(result))
}

// ip_ntoa(value) - convert integer to IPv4
fn fn_ip_ntoa(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_ntoa requires 1 argument')
	}
	a := args[0]
	n := match a {
		int { i64(a) }
		else { return error('ip_ntoa requires an integer') }
	}
	a1 := (n >> 24) & 0xFF
	a2 := (n >> 16) & 0xFF
	a3 := (n >> 8) & 0xFF
	a4 := n & 0xFF
	return VrlValue('${a1}.${a2}.${a3}.${a4}')
}

// ip_cidr_contains(cidr, ip) - cidr can be a string or array of strings
fn fn_ip_cidr_contains(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('ip_cidr_contains requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	ip := match a1 {
		string { a1 }
		else { return error('ip_cidr_contains second arg must be string') }
	}
	// Handle array of CIDRs
	match a0 {
		[]VrlValue {
			for item in a0 {
				ci := item
				cidr := match ci {
					string { ci }
					else { continue }
				}
				if ip_cidr_check(cidr, ip) {
					return VrlValue(true)
				}
			}
			return VrlValue(false)
		}
		string {
			return VrlValue(ip_cidr_check(a0, ip))
		}
		else {
			return error('ip_cidr_contains first arg must be string or array')
		}
	}
}

fn ip_cidr_check(cidr string, ip string) bool {
	slash_idx := cidr.index('/') or { return false }
	network := cidr[..slash_idx]
	prefix_len := cidr[slash_idx + 1..].int()

	if network.contains('.') && ip.contains('.') {
		net_int := ipv4_to_int(network) or { return false }
		ip_int := ipv4_to_int(ip) or { return false }
		if prefix_len < 0 || prefix_len > 32 {
			return false
		}
		mask := if prefix_len == 0 { u32(0) } else { ~u32(0) << (32 - prefix_len) }
		return (net_int & mask) == (ip_int & mask)
	}
	return false
}

fn ipv4_to_int(s string) !u32 {
	parts := s.split('.')
	if parts.len != 4 {
		return error('invalid IPv4')
	}
	mut result := u32(0)
	for p in parts {
		octet := p.int()
		if octet < 0 || octet > 255 {
			return error('invalid octet')
		}
		result = result * 256 + u32(octet)
	}
	return result
}

// ip_subnet(ip, subnet)
fn fn_ip_subnet(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('ip_subnet requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	ip := match a0 {
		string { a0 }
		else { return error('ip_subnet first arg must be string') }
	}
	subnet := match a1 {
		string { a1 }
		else { return error('ip_subnet second arg must be string') }
	}
	if ip.contains('.') {
		ip_int := ipv4_to_int(ip) or { return error('invalid IP: ${ip}') }
		mut mask := u32(0)
		if subnet.starts_with('/') {
			// CIDR notation
			prefix_len := subnet[1..].int()
			if prefix_len < 0 || prefix_len > 32 {
				return error('invalid prefix length')
			}
			mask = if prefix_len == 0 { u32(0) } else { ~u32(0) << (32 - prefix_len) }
		} else if subnet.contains('.') {
			// Dotted subnet mask
			mask = ipv4_to_int(subnet) or { return error('invalid subnet mask: ${subnet}') }
		} else {
			return error('invalid subnet: ${subnet}')
		}
		masked := ip_int & mask
		a_1 := (masked >> 24) & 0xFF
		a_2 := (masked >> 16) & 0xFF
		a_3 := (masked >> 8) & 0xFF
		a_4 := masked & 0xFF
		return VrlValue('${a_1}.${a_2}.${a_3}.${a_4}')
	}
	return error('IPv6 subnet not supported')
}

// ip_to_ipv6(value)
fn fn_ip_to_ipv6(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_to_ipv6 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ip_to_ipv6 requires a string') }
	}
	if s.contains(':') {
		return VrlValue(s)
	}
	// IPv4-mapped IPv6
	return VrlValue('::ffff:${s}')
}

// ipv6_to_ipv4(value)
fn fn_ipv6_to_ipv4(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ipv6_to_ipv4 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ipv6_to_ipv4 requires a string') }
	}
	if s.starts_with('::ffff:') {
		return VrlValue(s[7..])
	}
	return error('not an IPv4-mapped IPv6 address: ${s}')
}

// is_ipv4(value)
fn fn_is_ipv4(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return VrlValue(false)
	}
	a := args[0]
	s := match a {
		string { a }
		else { return VrlValue(false) }
	}
	parts := s.split('.')
	if parts.len != 4 {
		return VrlValue(false)
	}
	for p in parts {
		if p.len == 0 || p.len > 3 {
			return VrlValue(false)
		}
		for c in p.bytes() {
			if !c.is_digit() {
				return VrlValue(false)
			}
		}
		v := p.int()
		if v < 0 || v > 255 {
			return VrlValue(false)
		}
	}
	return VrlValue(true)
}

// is_ipv6(value)
fn fn_is_ipv6(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return VrlValue(false)
	}
	a := args[0]
	s := match a {
		string { a }
		else { return VrlValue(false) }
	}
	if !s.contains(':') {
		return VrlValue(false)
	}
	// Basic IPv6 validation
	parts := s.split(':')
	if parts.len < 3 || parts.len > 8 {
		return VrlValue(false)
	}
	return VrlValue(true)
}

// ip_version(value) - return 4 or 6
fn fn_ip_version(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_version requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ip_version requires a string') }
	}
	if s.contains(':') {
		return VrlValue('IPv6')
	}
	parts := s.split('.')
	if parts.len == 4 {
		return VrlValue('IPv4')
	}
	return error('not a valid IP address: ${s}')
}
