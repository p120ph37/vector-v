module vrl

import net

#include <netdb.h>
#include <sys/socket.h>

fn C.getnameinfo(sa voidptr, salen u32, host &u8, hostlen u32, serv &u8, servlen u32, flags int) int

// dns_lookup(value) — perform a DNS lookup and return IP addresses.
fn fn_dns_lookup(args []VrlValue, named map[string]VrlValue) !VrlValue {
	if args.len < 1 {
		return error('dns_lookup requires 1 argument')
	}
	a := args[0]
	hostname := match a {
		string { a }
		else { return error('dns_lookup requires a string') }
	}

	addrs := net.resolve_addrs(hostname + ':0', .unspec, .tcp) or {
		return error('query failed: ${err}')
	}

	mut results := []VrlValue{}
	for addr in addrs {
		s := addr.str()
		if colon := s.last_index(':') {
			ip := s[..colon]
			if ip.starts_with('[') && ip.ends_with(']') {
				results << VrlValue(ip[1..ip.len - 1])
			} else {
				results << VrlValue(ip)
			}
		} else {
			results << VrlValue(s)
		}
	}
	return VrlValue(results)
}

// reverse_dns(value) — perform a reverse DNS lookup on an IP address.
fn fn_reverse_dns(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('reverse_dns requires 1 argument')
	}
	a := args[0]
	ip_str := match a {
		string { a }
		else { return error('reverse_dns requires a string') }
	}

	if !ip_str.contains('.') && !ip_str.contains(':') {
		return error('unable to parse IP address: invalid IP address syntax')
	}

	// Build sockaddr from the IP string, then call getnameinfo.
	// We parse the IP ourselves and construct the C struct.
	mut host_buf := [1025]u8{}

	if ip_str.contains(':') {
		// IPv6 — build sockaddr_in6
		ip_bytes := ipv6_to_bytes(ip_str) or {
			return error('unable to parse IP address: ${err}')
		}
		mut sa := [64]u8{} // enough for sockaddr_in6 (28 bytes)
		// sin6_family = AF_INET6 (10) at offset 0 (u16, little-endian on Linux)
		sa[0] = 10
		sa[1] = 0
		// sin6_port at offset 2 (u16) = 0
		// sin6_flowinfo at offset 4 (u32) = 0
		// sin6_addr at offset 8 (16 bytes)
		for i in 0 .. 16 {
			sa[8 + i] = ip_bytes[i]
		}
		ret := C.getnameinfo(&sa[0], u32(28), &host_buf[0], 1025, unsafe { nil }, 0, 0)
		if ret != 0 {
			return error('unable to perform a lookup : getnameinfo failed')
		}
	} else {
		// IPv4 — build sockaddr_in
		parts := ip_str.split('.')
		if parts.len != 4 {
			return error('unable to parse IP address: invalid IPv4 address')
		}
		mut ip_bytes := [4]u8{}
		for i in 0 .. 4 {
			v := parts[i].int()
			if v < 0 || v > 255 {
				return error('unable to parse IP address: invalid IPv4 octet')
			}
			ip_bytes[i] = u8(v)
		}
		mut sa := [16]u8{} // sockaddr_in is 16 bytes
		// sin_family = AF_INET (2) at offset 0 (u16, little-endian on Linux)
		sa[0] = 2
		sa[1] = 0
		// sin_port at offset 2 (u16) = 0
		// sin_addr at offset 4 (4 bytes, network byte order)
		for i in 0 .. 4 {
			sa[4 + i] = ip_bytes[i]
		}
		ret := C.getnameinfo(&sa[0], u32(16), &host_buf[0], 1025, unsafe { nil }, 0, 0)
		if ret != 0 {
			return error('unable to perform a lookup : getnameinfo failed')
		}
	}

	return VrlValue(unsafe { cstring_to_vstring(&host_buf[0]) })
}
