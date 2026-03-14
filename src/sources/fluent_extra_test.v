module sources

// Tests for MsgpackReader and fluent protocol helpers

fn test_msgpack_reader_read_byte() {
	data := [u8(0x42)]
	mut r := MsgpackReader{
		data: data
	}
	b := r.read_byte()!
	assert b == 0x42
	assert r.pos == 1
}

fn test_msgpack_reader_read_byte_empty() {
	data := []u8{}
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_byte() {
		assert false, 'expected error on empty data'
	}
}

fn test_msgpack_reader_read_u16() {
	// 0x0100 = 256
	data := [u8(0x01), 0x00]
	mut r := MsgpackReader{
		data: data
	}
	val := r.read_u16()!
	assert val == 256
	assert r.pos == 2
}

fn test_msgpack_reader_read_u16_big_value() {
	// 0xFFFF = 65535
	data := [u8(0xFF), 0xFF]
	mut r := MsgpackReader{
		data: data
	}
	val := r.read_u16()!
	assert val == 65535
}

fn test_msgpack_reader_read_u32() {
	// 0x000186A0 = 100000
	data := [u8(0x00), 0x01, 0x86, 0xA0]
	mut r := MsgpackReader{
		data: data
	}
	val := r.read_u32()!
	assert val == 100000
	assert r.pos == 4
}

fn test_msgpack_reader_read_u32_truncated() {
	data := [u8(0x00), 0x01]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_u32() {
		assert false, 'expected error on truncated data'
	}
}

fn test_msgpack_reader_read_string_fixstr() {
	// fixstr "abc" = 0xa3 0x61 0x62 0x63
	data := [u8(0xa3), 0x61, 0x62, 0x63]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == 'abc'
}

fn test_msgpack_reader_read_string_str8() {
	// str8: 0xd9, length(1 byte), data
	mut data := [u8(0xd9), 0x05]
	data << 'hello'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == 'hello'
}

fn test_msgpack_reader_read_string_str16() {
	// str16: 0xda, length(2 bytes), data
	mut data := [u8(0xda), 0x00, 0x03]
	data << 'foo'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == 'foo'
}

fn test_msgpack_reader_read_string_str32() {
	// str32: 0xdb, length(4 bytes), data
	mut data := [u8(0xdb), 0x00, 0x00, 0x00, 0x03]
	data << 'bar'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == 'bar'
}

fn test_msgpack_reader_read_timestamp_positive_fixint() {
	data := [u8(100)]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 100
}

fn test_msgpack_reader_read_timestamp_uint8() {
	// uint8: 0xcc, value
	data := [u8(0xcc), 0xFE]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 254
}

fn test_msgpack_reader_read_timestamp_uint16() {
	// uint16: 0xcd, 2 bytes
	data := [u8(0xcd), 0x04, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 1024
}

fn test_msgpack_reader_read_timestamp_uint32() {
	// uint32: 0xce, 4 bytes
	data := [u8(0xce), 0x00, 0x01, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 65536
}

fn test_msgpack_reader_read_timestamp_int32() {
	// int32: 0xd2, 4 bytes (positive value)
	data := [u8(0xd2), 0x00, 0x00, 0x00, 0x0A]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 10
}

fn test_msgpack_reader_read_timestamp_negative_fixint() {
	// negative fixint: 0xff = -1
	data := [u8(0xff)]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == -1
}

fn test_msgpack_reader_read_timestamp_ext_eventtime() {
	// fixext 8: 0xd7, type=0, seconds(4 bytes), nanoseconds(4 bytes)
	data := [u8(0xd7), 0x00, 0x65, 0xdf, 0xd6, 0x80, 0x00, 0x00, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == i64(0x65dfd680)
}

fn test_msgpack_reader_read_value_as_string_nil() {
	data := [u8(0xc0)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == ''
}

fn test_msgpack_reader_read_value_as_string_bool() {
	// false
	data_false := [u8(0xc2)]
	mut r1 := MsgpackReader{
		data: data_false
	}
	assert r1.read_value_as_string()! == 'false'

	// true
	data_true := [u8(0xc3)]
	mut r2 := MsgpackReader{
		data: data_true
	}
	assert r2.read_value_as_string()! == 'true'
}

fn test_msgpack_reader_read_value_as_string_positive_fixint() {
	data := [u8(42)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '42'
}

fn test_msgpack_reader_read_value_as_string_negative_fixint() {
	// 0xe0 = -32
	data := [u8(0xe0)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '-32'
}

fn test_msgpack_reader_read_value_as_string_fixstr() {
	// fixstr "hi"
	data := [u8(0xa2), 0x68, 0x69]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'hi'
}

fn test_msgpack_reader_read_value_as_string_uint8() {
	// uint8: 0xcc, 200
	data := [u8(0xcc), 0xC8]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '200'
}

fn test_msgpack_reader_read_value_as_string_float64() {
	// float64: 0xcb + 8 bytes
	data := [u8(0xcb), 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '0.0'
}

fn test_msgpack_reader_skip_value_nil() {
	data := [u8(0xc0)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 1
}

fn test_msgpack_reader_skip_value_true_false() {
	data := [u8(0xc2), 0xc3]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 1
	r.skip_value()!
	assert r.pos == 2
}

fn test_msgpack_reader_skip_value_positive_fixint() {
	data := [u8(0x7f)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 1
}

fn test_msgpack_reader_skip_value_negative_fixint() {
	data := [u8(0xe5)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 1
}

fn test_msgpack_reader_skip_value_fixstr() {
	// fixstr "hi" = 0xa2 + 2 bytes
	data := [u8(0xa2), 0x68, 0x69]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 3
}

fn test_msgpack_reader_skip_value_uint32() {
	// uint32: 0xce + 4 bytes
	data := [u8(0xce), 0x00, 0x00, 0x00, 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_float64() {
	// float64: 0xcb + 8 bytes
	data := [u8(0xcb), 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 9
}

fn test_msgpack_reader_skip_value_fixmap() {
	// fixmap(1): {fixstr("k"): fixint(1)}
	data := [u8(0x81), 0xa1, u8(`k`), 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 4
}

fn test_msgpack_reader_skip_value_fixarray() {
	// fixarray(2): [fixint(1), fixint(2)]
	data := [u8(0x92), 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 3
}

fn test_is_msgpack_int_or_ext() {
	// positive fixint
	assert is_msgpack_int_or_ext(0x00) == true
	assert is_msgpack_int_or_ext(0x7f) == true
	// negative fixint
	assert is_msgpack_int_or_ext(0xe0) == true
	assert is_msgpack_int_or_ext(0xff) == true
	// uint8
	assert is_msgpack_int_or_ext(0xcc) == true
	// uint32
	assert is_msgpack_int_or_ext(0xce) == true
	// ext types
	assert is_msgpack_int_or_ext(0xd7) == true
	// strings should not match
	assert is_msgpack_int_or_ext(0xa5) == false
	// nil should not match
	assert is_msgpack_int_or_ext(0xc0) == false
}

fn test_is_msgpack_bin_or_str() {
	// fixstr
	assert is_msgpack_bin_or_str(0xa0) == true
	assert is_msgpack_bin_or_str(0xbf) == true
	// bin8
	assert is_msgpack_bin_or_str(0xc4) == true
	// bin16
	assert is_msgpack_bin_or_str(0xc5) == true
	// bin32
	assert is_msgpack_bin_or_str(0xc6) == true
	// str8
	assert is_msgpack_bin_or_str(0xd9) == true
	// str16
	assert is_msgpack_bin_or_str(0xda) == true
	// str32
	assert is_msgpack_bin_or_str(0xdb) == true
	// non-matching
	assert is_msgpack_bin_or_str(0xc0) == false
	assert is_msgpack_bin_or_str(0xce) == false
}

fn test_msgpack_reader_read_array_len_array16() {
	// array16: 0xdc, 2 bytes length
	data := [u8(0xdc), 0x00, 0x03]
	mut r := MsgpackReader{
		data: data
	}
	len := r.read_array_len()!
	assert len == 3
}

fn test_msgpack_reader_read_array_len_invalid() {
	// nil is not an array
	data := [u8(0xc0)]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_array_len() {
		assert false, 'expected error for non-array type'
	}
}

fn test_decode_empty_data_error() {
	if _ := decode_fluent_message([]u8{}) {
		assert false, 'expected error for empty data'
	}
}

fn test_encode_msgpack_ack_short_chunk() {
	ack := encode_msgpack_ack('hi')
	assert ack[0] == 0x81 // fixmap 1
	assert ack[1] == 0xa3 // fixstr "ack" len 3
}

fn test_encode_msgpack_ack_medium_chunk() {
	// 50 chars to trigger str8 encoding path (chunk.len >= 32)
	chunk := 'a'.repeat(50)
	ack := encode_msgpack_ack(chunk)
	assert ack[0] == 0x81
	// After "ack" key (4 bytes: 0xa3, a, c, k), value should use 0xd9
	assert ack[5] == 0xd9
}
