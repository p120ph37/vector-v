module sources

// Test msgpack decoder for fluent protocol

fn test_msgpack_reader_read_fixstr() {
	// fixstr "hi" = 0xa2 0x68 0x69
	data := [u8(0xa2), 0x68, 0x69]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == 'hi'
	assert r.pos == 3
}

fn test_msgpack_reader_read_positive_fixint() {
	data := [u8(42)]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 42
}

fn test_msgpack_reader_read_uint16() {
	// uint16: 0xcd, high, low = 256
	data := [u8(0xcd), 0x01, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 256
}

fn test_msgpack_reader_read_uint32() {
	// uint32: 0xce, 4 bytes = 100000
	data := [u8(0xce), 0x00, 0x01, 0x86, 0xa0]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 100000
}

fn test_msgpack_reader_read_fixmap() {
	// fixmap(1): {fixstr("k"): fixstr("v")}
	data := [u8(0x81), 0xa1, u8(`k`), 0xa1, u8(`v`)]
	mut r := MsgpackReader{
		data: data
	}
	m := r.read_map()!
	assert m.len == 1
	assert m['k'] == 'v'
}

fn test_msgpack_reader_read_fixarray() {
	// fixarray(2)
	data := [u8(0x92)]
	mut r := MsgpackReader{
		data: data
	}
	len := r.read_array_len()!
	assert len == 2
}

fn test_decode_heartbeat() {
	data := [u8(0xc0)]
	result := decode_fluent_message(data)!
	assert result.events.len == 0
	assert result.consumed == 1
}

fn test_decode_fluent_message_mode() {
	// Build a simple Message: [tag, timestamp, record]
	// fixarray(3), fixstr "test.tag", positive fixint 1234 (use uint32),
	// fixmap(1) { fixstr "msg": fixstr "hello" }
	mut data := []u8{}
	data << 0x93 // fixarray 3
	// tag: "test.tag" (8 bytes)
	data << 0xa8 // fixstr len 8
	data << 'test.tag'.bytes()
	// timestamp: uint32 1710000000
	data << 0xce
	data << u8(0x65)
	data << u8(0xdf)
	data << u8(0xd6)
	data << u8(0x80)
	// record: {"msg": "hello"}
	data << 0x81 // fixmap 1
	data << 0xa3 // fixstr 3
	data << 'msg'.bytes()
	data << 0xa5 // fixstr 5
	data << 'hello'.bytes()

	result := decode_fluent_message(data)!
	assert result.events.len == 1
}

fn test_decode_fluent_forward_mode() {
	// Forward: [tag, [[ts, record], [ts, record]]]
	mut data := []u8{}
	data << 0x92 // fixarray 2
	// tag
	data << 0xa4 // fixstr 4
	data << 'test'.bytes()
	// entries array
	data << 0x92 // fixarray 2 (two entries)
	// entry 1: [ts, record]
	data << 0x92 // fixarray 2
	data << 0x01 // timestamp 1
	data << 0x81 // fixmap 1
	data << 0xa1
	data << u8(`a`)
	data << 0xa1
	data << u8(`1`)
	// entry 2: [ts, record]
	data << 0x92 // fixarray 2
	data << 0x02 // timestamp 2
	data << 0x81 // fixmap 1
	data << 0xa1
	data << u8(`b`)
	data << 0xa1
	data << u8(`2`)

	result := decode_fluent_message(data)!
	assert result.events.len == 2
}

fn test_encode_msgpack_ack() {
	ack := encode_msgpack_ack('abc')
	assert ack.len > 0
	assert ack[0] == 0x81 // fixmap 1
}

fn test_new_fluent_default() {
	s := new_fluent(map[string]string{})
	assert s.address == '0.0.0.0:24224'
}

fn test_new_fluent_custom_address() {
	s := new_fluent({
		'address': '127.0.0.1:24225'
	})
	assert s.address == '127.0.0.1:24225'
}
