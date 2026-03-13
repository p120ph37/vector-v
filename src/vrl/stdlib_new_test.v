module vrl

// Tests for newly implemented VRL functions.

fn test_ip_ntop_ipv4() {
	data := [u8(1), 2, 3, 4].bytestr()
	result := fn_ip_ntop([VrlValue(data)]) or { panic(err.msg()) }
	assert result == VrlValue('1.2.3.4')
}

fn test_ip_ntop_ipv6_loopback() {
	mut data := []u8{len: 16}
	data[15] = 1
	result := fn_ip_ntop([VrlValue(data.bytestr())]) or { panic(err.msg()) }
	s := result as string
	assert s == '::1', 'got: ${s}'
}

fn test_ip_ntop_bad_len() {
	data := [u8(1), 2, 3].bytestr()
	fn_ip_ntop([VrlValue(data)]) or {
		assert err.msg().contains('4 or 16 bytes')
		return
	}
	panic('expected error')
}

fn test_ip_pton_ipv4() {
	result := fn_ip_pton([VrlValue('1.2.3.4')]) or { panic(err.msg()) }
	s := result as string
	bytes := s.bytes()
	assert bytes.len == 4
	assert bytes[0] == 1
	assert bytes[1] == 2
	assert bytes[2] == 3
	assert bytes[3] == 4
}

fn test_ip_pton_ipv6() {
	result := fn_ip_pton([VrlValue('::1')]) or { panic(err.msg()) }
	s := result as string
	bytes := s.bytes()
	assert bytes.len == 16
	assert bytes[15] == 1
	for i in 0 .. 15 {
		assert bytes[i] == 0
	}
}

fn test_ip_roundtrip_ipv4() {
	original := '10.0.0.1'
	binary := fn_ip_pton([VrlValue(original)]) or { panic(err.msg()) }
	result := fn_ip_ntop([binary]) or { panic(err.msg()) }
	assert result == VrlValue(original)
}

fn test_uuid_from_friendly_id() {
	result := fn_uuid_from_friendly_id([VrlValue('3s87yEvnmkiPBMHsj8bwwc')]) or {
		panic(err.msg())
	}
	s := result as string
	assert s == '7f41deed-d5e2-8b5e-7a13-ab4ff93cfad2', 'got: ${s}'
}

fn test_uuid_from_friendly_id_invalid() {
	fn_uuid_from_friendly_id([VrlValue('invalid!chars')]) or {
		assert err.msg().contains('failed to decode friendly id')
		return
	}
	panic('expected error')
}

fn test_community_id_tcp() {
	result := fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('1.2.3.4')
		'destination_ip':    VrlValue('5.6.7.8')
		'protocol':          VrlValue(i64(6))
		'source_port':       VrlValue(i64(1122))
		'destination_port':  VrlValue(i64(3344))
	}) or { panic(err.msg()) }
	s := result as string
	assert s == '1:wCb3OG7yAFWelaUydu0D+125CLM=', 'got: ${s}'
}

fn test_community_id_tcp_reverse() {
	result := fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('5.6.7.8')
		'destination_ip':    VrlValue('1.2.3.4')
		'protocol':          VrlValue(i64(6))
		'source_port':       VrlValue(i64(3344))
		'destination_port':  VrlValue(i64(1122))
	}) or { panic(err.msg()) }
	s := result as string
	assert s == '1:wCb3OG7yAFWelaUydu0D+125CLM=', 'got: ${s}'
}

fn test_community_id_udp() {
	result := fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('1.2.3.4')
		'destination_ip':    VrlValue('5.6.7.8')
		'protocol':          VrlValue(i64(17))
		'source_port':       VrlValue(i64(1122))
		'destination_port':  VrlValue(i64(3344))
	}) or { panic(err.msg()) }
	s := result as string
	assert s == '1:0Mu9InQx6z4ZiCZM/7HXi2WMhOg=', 'got: ${s}'
}

fn test_community_id_rsvp() {
	result := fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('1.2.3.4')
		'destination_ip':    VrlValue('5.6.7.8')
		'protocol':          VrlValue(i64(46))
	}) or { panic(err.msg()) }
	s := result as string
	assert s == '1:ikv3kmf89luf73WPz1jOs49S768=', 'got: ${s}'
}

fn test_community_id_tcp_no_ports() {
	fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('1.2.3.4')
		'destination_ip':    VrlValue('5.6.7.8')
		'protocol':          VrlValue(i64(6))
	}) or {
		assert err.msg().contains('src port and dst port should be set')
		return
	}
	panic('expected error')
}

fn test_community_id_tcp_seed_1() {
	result := fn_community_id([]VrlValue{}, {
		'source_ip':         VrlValue('1.2.3.4')
		'destination_ip':    VrlValue('5.6.7.8')
		'protocol':          VrlValue(i64(6))
		'source_port':       VrlValue(i64(1122))
		'destination_port':  VrlValue(i64(3344))
		'seed':              VrlValue(i64(1))
	}) or { panic(err.msg()) }
	s := result as string
	assert s == '1:HhA1B+6CoLbiKPEs5nhNYN4XWfk=', 'got: ${s}'
}

fn test_encode_charset_latin1() {
	result := fn_encode_charset([VrlValue('hello')], {
		'to_charset': VrlValue('ISO-8859-1')
	}) or { panic(err.msg()) }
	s := result as string
	assert s == 'hello', 'got: ${s}'
}

fn test_decode_charset_latin1() {
	result := fn_decode_charset([VrlValue('hello')], {
		'from_charset': VrlValue('ISO-8859-1')
	}) or { panic(err.msg()) }
	s := result as string
	assert s == 'hello', 'got: ${s}'
}
