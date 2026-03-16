module sources

fn test_new_dnstap_defaults() {
	s := new_dnstap(map[string]string{}) or { panic(err.str()) }
	assert s.socket_path == ''
	assert s.host == '0.0.0.0'
	assert s.port == 6000
	assert s.mode == 'tcp'
	assert s.max_frame_length == 102400
	assert s.content_type == 'protobuf:dnstap.Dnstap'
}

fn test_new_dnstap_unix_mode() {
	s := new_dnstap({
		'mode':        'unix'
		'socket_path': '/var/run/dnstap.sock'
	}) or { panic(err.str()) }
	assert s.mode == 'unix'
	assert s.socket_path == '/var/run/dnstap.sock'
}

fn test_new_dnstap_unix_mode_requires_socket_path() {
	new_dnstap({
		'mode': 'unix'
	}) or {
		assert err.msg().contains('socket_path is required')
		return
	}
	assert false, 'expected error for missing socket_path in unix mode'
}

fn test_new_dnstap_tcp_mode_custom() {
	s := new_dnstap({
		'mode': 'tcp'
		'host': '127.0.0.1'
		'port': '8053'
	}) or { panic(err.str()) }
	assert s.mode == 'tcp'
	assert s.host == '127.0.0.1'
	assert s.port == 8053
}

fn test_new_dnstap_invalid_mode() {
	new_dnstap({
		'mode': 'udp'
	}) or {
		assert err.msg().contains("mode must be 'tcp' or 'unix'")
		return
	}
	assert false, 'expected error for invalid mode'
}

fn test_new_dnstap_negative_port_clamps() {
	s := new_dnstap({
		'port': '-5'
	}) or { panic(err.str()) }
	assert s.port == 6000
}

fn test_new_dnstap_negative_frame_length_clamps() {
	s := new_dnstap({
		'max_frame_length': '-100'
	}) or { panic(err.str()) }
	assert s.max_frame_length == 102400
}

fn test_new_dnstap_custom_content_type() {
	s := new_dnstap({
		'content_type': 'protobuf:custom.Type'
	}) or { panic(err.str()) }
	assert s.content_type == 'protobuf:custom.Type'
}

fn test_new_dnstap_all_options() {
	s := new_dnstap({
		'socket_path':      '/tmp/dns.sock'
		'host':             '10.0.0.1'
		'port':             '7000'
		'mode':             'unix'
		'max_frame_length': '204800'
		'content_type':     'protobuf:my.Dnstap'
	}) or { panic(err.str()) }
	assert s.socket_path == '/tmp/dns.sock'
	assert s.host == '10.0.0.1'
	assert s.port == 7000
	assert s.mode == 'unix'
	assert s.max_frame_length == 204800
	assert s.content_type == 'protobuf:my.Dnstap'
}

fn test_dnstap_message_type_name_all() {
	assert dnstap_message_type_name(1) == 'AUTH_QUERY'
	assert dnstap_message_type_name(2) == 'AUTH_RESPONSE'
	assert dnstap_message_type_name(3) == 'RESOLVER_QUERY'
	assert dnstap_message_type_name(4) == 'RESOLVER_RESPONSE'
	assert dnstap_message_type_name(5) == 'CLIENT_QUERY'
	assert dnstap_message_type_name(6) == 'CLIENT_RESPONSE'
	assert dnstap_message_type_name(7) == 'FORWARDER_QUERY'
	assert dnstap_message_type_name(8) == 'FORWARDER_RESPONSE'
	assert dnstap_message_type_name(9) == 'STUB_QUERY'
	assert dnstap_message_type_name(10) == 'STUB_RESPONSE'
	assert dnstap_message_type_name(11) == 'TOOL_QUERY'
	assert dnstap_message_type_name(12) == 'TOOL_RESPONSE'
	assert dnstap_message_type_name(0) == 'UNKNOWN'
	assert dnstap_message_type_name(99) == 'UNKNOWN'
	assert dnstap_message_type_name(-1) == 'UNKNOWN'
}

fn test_read_protobuf_varint_single_byte() {
	// Single byte varint: value 5 => 0x05
	data := [u8(0x05)]
	val, consumed := read_protobuf_varint(data, 0)
	assert val == 5
	assert consumed == 1
}

fn test_read_protobuf_varint_multi_byte() {
	// Multi-byte varint: value 300 => 0xAC 0x02
	// 300 = 0b100101100
	// byte 0: 0b10101100 = 0xAC (continuation bit set, lower 7 bits = 0b0101100 = 44)
	// byte 1: 0b00000010 = 0x02 (no continuation, 7 bits = 2)
	// value = 44 + (2 << 7) = 44 + 256 = 300
	data := [u8(0xAC), 0x02]
	val, consumed := read_protobuf_varint(data, 0)
	assert val == 300
	assert consumed == 2
}

fn test_read_protobuf_varint_empty() {
	data := []u8{}
	val, consumed := read_protobuf_varint(data, 0)
	assert val == 0
	assert consumed == 0
}

fn test_parse_frame_stream_control_start() {
	// Control frame: escape (4 zero bytes) + control length (4 bytes) + control type START=2 (4 bytes)
	mut data := []u8{len: 12}
	// Escape sequence: 4 zero bytes
	data[0] = 0x00
	data[1] = 0x00
	data[2] = 0x00
	data[3] = 0x00
	// Control frame length: 4 (just the control type)
	data[4] = 0x00
	data[5] = 0x00
	data[6] = 0x00
	data[7] = 0x04
	// Control type: START = 2
	data[8] = 0x00
	data[9] = 0x00
	data[10] = 0x00
	data[11] = 0x02

	ctrl := parse_frame_stream_control(data)
	assert ctrl.control_type == 2
	assert ctrl.content_type == ''
}

fn test_parse_frame_stream_control_stop() {
	mut data := []u8{len: 12}
	data[0] = 0x00
	data[1] = 0x00
	data[2] = 0x00
	data[3] = 0x00
	data[4] = 0x00
	data[5] = 0x00
	data[6] = 0x00
	data[7] = 0x04
	// Control type: STOP = 3
	data[8] = 0x00
	data[9] = 0x00
	data[10] = 0x00
	data[11] = 0x03

	ctrl := parse_frame_stream_control(data)
	assert ctrl.control_type == 3
}

fn test_parse_frame_stream_control_ready() {
	// READY control frame with content type
	ct := 'protobuf:dnstap.Dnstap'.bytes()
	ct_len := ct.len
	mut data := []u8{len: 20 + ct_len}
	// Escape
	data[0] = 0x00
	data[1] = 0x00
	data[2] = 0x00
	data[3] = 0x00
	// Control length
	total := 4 + 4 + 4 + ct_len // type + field_type + ct_len + ct
	data[4] = u8(total >> 24)
	data[5] = u8(total >> 16)
	data[6] = u8(total >> 8)
	data[7] = u8(total)
	// Control type: READY = 4
	data[8] = 0x00
	data[9] = 0x00
	data[10] = 0x00
	data[11] = 0x04
	// Content type field type = 1
	data[12] = 0x00
	data[13] = 0x00
	data[14] = 0x00
	data[15] = 0x01
	// Content type length
	data[16] = u8(ct_len >> 24)
	data[17] = u8(ct_len >> 16)
	data[18] = u8(ct_len >> 8)
	data[19] = u8(ct_len)
	// Content type bytes
	for i, b in ct {
		data[20 + i] = b
	}

	ctrl := parse_frame_stream_control(data)
	assert ctrl.control_type == 4
	assert ctrl.content_type == 'protobuf:dnstap.Dnstap'
}

fn test_parse_dnstap_fields_basic() {
	// Build a minimal protobuf message with:
	// Field 1, wire type 2 (length-delimited): identity = "ns1"
	// Field 14, wire type 0 (varint): message_type = 5 (CLIENT_QUERY)
	mut data := []u8{}

	// Field 1, wire type 2: tag = (1 << 3) | 2 = 0x0A
	data << 0x0A
	// Length: 3
	data << 0x03
	// "ns1"
	data << `n`
	data << `s`
	data << `1`

	// Field 14, wire type 0: tag = (14 << 3) | 0 = 112 = 0x70
	data << 0x70
	// Value: 5 (CLIENT_QUERY)
	data << 0x05

	fields := parse_dnstap_fields(data)
	assert fields['1'] == 'ns1'
	assert fields['14'] == '5'
}
