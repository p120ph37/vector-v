module vrl

// ip_ntop(value) - convert binary bytes (4 or 16) to IP address string
// Mimics C inet_ntop().
fn fn_ip_ntop(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_ntop requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ip_ntop requires a string (bytes)') }
	}
	data := s.bytes()
	if data.len == 4 {
		// IPv4
		return VrlValue('${data[0]}.${data[1]}.${data[2]}.${data[3]}')
	} else if data.len == 16 {
		// IPv6 — format as 8 colon-separated 16-bit hex groups
		mut groups := []string{cap: 8}
		for i := 0; i < 16; i += 2 {
			val := (u16(data[i]) << 8) | u16(data[i + 1])
			groups << val.hex()
		}
		// Compress longest run of zero groups (RFC 5952)
		return VrlValue(ipv6_compress(groups))
	}
	return error('"value" must be of length 4 or 16 bytes')
}

// ipv6_compress compresses an array of 8 hex groups into canonical IPv6 notation.
fn ipv6_compress(groups []string) string {
	// Find the longest consecutive run of "0" groups
	mut best_start := -1
	mut best_len := 0
	mut cur_start := -1
	mut cur_len := 0
	for i, g in groups {
		if g == '0' {
			if cur_start < 0 {
				cur_start = i
				cur_len = 1
			} else {
				cur_len++
			}
			if cur_len > best_len {
				best_start = cur_start
				best_len = cur_len
			}
		} else {
			cur_start = -1
			cur_len = 0
		}
	}
	if best_len < 2 {
		// No compression needed
		return groups.join(':')
	}
	mut parts := []string{}
	if best_start == 0 {
		parts << ''
	}
	for i := 0; i < best_start; i++ {
		parts << groups[i]
	}
	parts << ''
	for i := best_start + best_len; i < 8; i++ {
		parts << groups[i]
	}
	if best_start + best_len == 8 {
		parts << ''
	}
	return parts.join(':')
}

// ip_pton(value) - convert IP address string to binary bytes
// Mimics C inet_pton().
fn fn_ip_pton(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('ip_pton requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('ip_pton requires a string') }
	}
	if s.contains(':') {
		// IPv6
		bytes := ipv6_to_bytes(s) or { return error('unable to parse IP address: ${err}') }
		return VrlValue(bytes.bytestr())
	} else if s.contains('.') {
		// IPv4
		parts := s.split('.')
		if parts.len != 4 {
			return error('unable to parse IP address: invalid IPv4 address')
		}
		mut bytes := []u8{cap: 4}
		for p in parts {
			v := p.int()
			if v < 0 || v > 255 || (p.len > 1 && p[0] == `0`) || p.len == 0 {
				return error('unable to parse IP address: invalid IPv4 octet')
			}
			// Verify it's actually numeric
			for c in p.bytes() {
				if !c.is_digit() {
					return error('unable to parse IP address: invalid IPv4 octet')
				}
			}
			bytes << u8(v)
		}
		return VrlValue(bytes.bytestr())
	}
	return error('unable to parse IP address: invalid IP address syntax')
}

// ipv6_to_bytes parses an IPv6 string into 16 bytes.
fn ipv6_to_bytes(s string) ![]u8 {
	// Handle :: expansion
	mut left := s
	mut right := ''
	if dci := s.index('::') {
		left = s[..dci]
		right = s[dci + 2..]
	}

	mut groups := []u16{}
	if left.len > 0 {
		for part in left.split(':') {
			groups << parse_hex_u16(part) or {
				return error('invalid IPv6 group: ${part}')
			}
		}
	}
	mut right_groups := []u16{}
	if right.len > 0 {
		for part in right.split(':') {
			right_groups << parse_hex_u16(part) or {
				return error('invalid IPv6 group: ${part}')
			}
		}
	}
	// Fill with zeros
	total := groups.len + right_groups.len
	if total > 8 {
		return error('too many groups in IPv6 address')
	}
	for _ in 0 .. (8 - total) {
		groups << u16(0)
	}
	groups << right_groups

	mut result := []u8{cap: 16}
	for g in groups {
		result << u8(g >> 8)
		result << u8(g & 0xFF)
	}
	return result
}

fn parse_hex_u16(s string) !u16 {
	if s.len == 0 || s.len > 4 {
		return error('invalid hex group')
	}
	mut val := u16(0)
	for c in s.bytes() {
		val <<= 4
		if c >= `0` && c <= `9` {
			val |= u16(c - `0`)
		} else if c >= `a` && c <= `f` {
			val |= u16(c - `a` + 10)
		} else if c >= `A` && c <= `F` {
			val |= u16(c - `A` + 10)
		} else {
			return error('invalid hex char')
		}
	}
	return val
}
