module sources

// Additional tests for fluent.v covering uncovered msgpack decoding paths,
// error handling, protocol message parsing, and edge cases.

// ---- MsgpackReader: array32 (0xdd) ----

fn test_msgpack_reader_read_array_len_array32() {
	// array32: 0xdd, 4 bytes length = 2
	data := [u8(0xdd), 0x00, 0x00, 0x00, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	len := r.read_array_len()!
	assert len == 2
}

// ---- MsgpackReader: read_bytes variants ----

fn test_msgpack_reader_read_bytes_bin8() {
	// bin8: 0xc4, length(1 byte), data
	mut data := [u8(0xc4), 0x03]
	data << `a`
	data << `b`
	data << `c`
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 3
	assert result.bytestr() == 'abc'
}

fn test_msgpack_reader_read_bytes_bin16() {
	// bin16: 0xc5, length(2 bytes), data
	mut data := [u8(0xc5), 0x00, 0x04]
	data << 'test'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 4
	assert result.bytestr() == 'test'
}

fn test_msgpack_reader_read_bytes_bin32() {
	// bin32: 0xc6, length(4 bytes), data
	mut data := [u8(0xc6), 0x00, 0x00, 0x00, 0x02]
	data << `x`
	data << `y`
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 2
	assert result.bytestr() == 'xy'
}

fn test_msgpack_reader_read_bytes_str8() {
	// str8 used as bytes: 0xd9, length(1 byte), data
	mut data := [u8(0xd9), 0x02]
	data << `h`
	data << `i`
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 2
	assert result.bytestr() == 'hi'
}

fn test_msgpack_reader_read_bytes_str16() {
	// str16 used as bytes: 0xda, length(2 bytes), data
	mut data := [u8(0xda), 0x00, 0x03]
	data << 'foo'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 3
	assert result.bytestr() == 'foo'
}

fn test_msgpack_reader_read_bytes_str32() {
	// str32 used as bytes: 0xdb, length(4 bytes), data
	mut data := [u8(0xdb), 0x00, 0x00, 0x00, 0x03]
	data << 'bar'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.len == 3
	assert result.bytestr() == 'bar'
}

fn test_msgpack_reader_read_bytes_fixstr() {
	// fixstr used as bin: 0xa3 (len 3)
	data := [u8(0xa3), u8(`a`), u8(`b`), u8(`c`)]
	mut r := MsgpackReader{
		data: data
	}
	result := r.read_bytes()!
	assert result.bytestr() == 'abc'
}

fn test_msgpack_reader_read_bytes_invalid_type() {
	// 0xcc is uint8, not bin/str
	data := [u8(0xcc), 0x42]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_bytes() {
		assert false, 'expected error for invalid bin/str type'
	}
}

fn test_msgpack_reader_read_bytes_truncated() {
	// bin8 with length 10 but only 2 bytes of data
	data := [u8(0xc4), 0x0A, 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_bytes() {
		assert false, 'expected error for truncated bytes'
	}
}

// ---- MsgpackReader: read_timestamp edge cases ----

fn test_msgpack_reader_read_timestamp_uint64() {
	// uint64: 0xcf, 8 bytes
	data := [u8(0xcf), 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 256
}

fn test_msgpack_reader_read_timestamp_uint64_truncated() {
	// uint64 header but not enough bytes
	data := [u8(0xcf), 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_timestamp() {
		assert false, 'expected error for truncated uint64'
	}
}

fn test_msgpack_reader_read_timestamp_ext_unknown_type() {
	// fixext 8 with type != 0 (unknown ext type)
	data := [u8(0xd7), 0x05, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == 0, 'unknown ext type should return 0'
}

fn test_msgpack_reader_read_timestamp_invalid_type() {
	// 0x90 is fixarray, not valid for timestamp
	data := [u8(0x90)]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_timestamp() {
		assert false, 'expected error for non-timestamp type'
	}
}

fn test_msgpack_reader_read_timestamp_int32_negative() {
	// int32: 0xd2, 0xFFFFFFFF = -1
	data := [u8(0xd2), 0xFF, 0xFF, 0xFF, 0xFF]
	mut r := MsgpackReader{
		data: data
	}
	ts := r.read_timestamp()!
	assert ts == -1
}

// ---- MsgpackReader: read_map edge cases ----

fn test_msgpack_reader_read_map_map16() {
	// map16: 0xde, 2 bytes count = 1, then key-value pair
	mut data := [u8(0xde), 0x00, 0x01]
	data << 0xa3 // fixstr "key"
	data << 'key'.bytes()
	data << 0xa3 // fixstr "val"
	data << 'val'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	m := r.read_map()!
	assert m.len == 1
	assert m['key'] == 'val'
}

fn test_msgpack_reader_read_map_map32() {
	// map32: 0xdf, 4 bytes count = 1, then key-value pair
	mut data := [u8(0xdf), 0x00, 0x00, 0x00, 0x01]
	data << 0xa1 // fixstr "a"
	data << u8(`a`)
	data << 0xa1 // fixstr "b"
	data << u8(`b`)
	mut r := MsgpackReader{
		data: data
	}
	m := r.read_map()!
	assert m.len == 1
	assert m['a'] == 'b'
}

fn test_msgpack_reader_read_map_invalid_type() {
	data := [u8(0xcc)] // uint8, not a map
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_map() {
		assert false, 'expected error for non-map type'
	}
}

fn test_msgpack_reader_read_map_empty() {
	// fixmap(0)
	data := [u8(0x80)]
	mut r := MsgpackReader{
		data: data
	}
	m := r.read_map()!
	assert m.len == 0
}

// ---- read_value_as_string: coverage for various types ----

fn test_msgpack_reader_read_value_as_string_uint16() {
	// uint16: 0xcd, 0x01, 0x00 = 256
	data := [u8(0xcd), 0x01, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '256'
}

fn test_msgpack_reader_read_value_as_string_uint32() {
	// uint32: 0xce, 4 bytes = 65536
	data := [u8(0xce), 0x00, 0x01, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '65536'
}

fn test_msgpack_reader_read_value_as_string_int8() {
	// int8: 0xd0, value = -1 (0xFF)
	data := [u8(0xd0), 0xFF]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '-1'
}

fn test_msgpack_reader_read_value_as_string_int16() {
	// int16: 0xd1, value = -256 (0xFF00)
	data := [u8(0xd1), 0xFF, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '-256'
}

fn test_msgpack_reader_read_value_as_string_int32() {
	// int32: 0xd2, value = 100 (0x00000064)
	data := [u8(0xd2), 0x00, 0x00, 0x00, 0x64]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == '100'
}

fn test_msgpack_reader_read_value_as_string_float32() {
	// float32: 0xca + 4 bytes (bits of 1.0 = 0x3F800000)
	data := [u8(0xca), 0x3F, 0x80, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	// Returns bits as string
	assert s == '${u32(0x3F800000)}'
}

fn test_msgpack_reader_read_value_as_string_bin8() {
	// bin8: 0xc4, len=2, data="ab"
	data := [u8(0xc4), 0x02, u8(`a`), u8(`b`)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'ab'
}

fn test_msgpack_reader_read_value_as_string_bin16() {
	// bin16: 0xc5, len=2 (2 byte length), data="cd"
	data := [u8(0xc5), 0x00, 0x02, u8(`c`), u8(`d`)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'cd'
}

fn test_msgpack_reader_read_value_as_string_bin32() {
	// bin32: 0xc6, len=1 (4 byte length), data="e"
	data := [u8(0xc6), 0x00, 0x00, 0x00, 0x01, u8(`e`)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'e'
}

fn test_msgpack_reader_read_value_as_string_str8() {
	// str8: 0xd9, len=3, data="xyz"
	mut data := [u8(0xd9), 0x03]
	data << 'xyz'.bytes()
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'xyz'
}

fn test_msgpack_reader_read_value_as_string_str16() {
	// str16: 0xda, len(2 bytes)=2, data="ok"
	data := [u8(0xda), 0x00, 0x02, u8(`o`), u8(`k`)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'ok'
}

fn test_msgpack_reader_read_value_as_string_str32() {
	// str32: 0xdb, len(4 bytes)=2, data="hi"
	data := [u8(0xdb), 0x00, 0x00, 0x00, 0x02, u8(`h`), u8(`i`)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == 'hi'
}

fn test_msgpack_reader_read_value_as_string_empty_error() {
	data := []u8{}
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_value_as_string() {
		assert false, 'expected error on empty data'
	}
}

fn test_msgpack_reader_read_value_as_string_float64_truncated() {
	// float64 header but not enough bytes
	data := [u8(0xcb), 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_value_as_string() {
		assert false, 'expected error for truncated float64'
	}
}

fn test_msgpack_reader_read_value_as_string_skip_fixarray() {
	// fixarray with 1 element (fixint 5): should skip and return ''
	data := [u8(0x91), 0x05]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == ''
}

fn test_msgpack_reader_read_value_as_string_skip_fixmap() {
	// fixmap(1) {fixint(1): fixint(2)}: should skip and return ''
	data := [u8(0x81), 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_value_as_string()!
	assert s == ''
}

// ---- skip_value: additional coverage ----

fn test_msgpack_reader_skip_value_uint8() {
	// uint8: 0xcc + 1 byte
	data := [u8(0xcc), 0xFF]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 2
}

fn test_msgpack_reader_skip_value_int8() {
	// int8: 0xd0 + 1 byte
	data := [u8(0xd0), 0x80]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 2
}

fn test_msgpack_reader_skip_value_uint16() {
	// uint16: 0xcd + 2 bytes
	data := [u8(0xcd), 0x01, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 3
}

fn test_msgpack_reader_skip_value_int16() {
	// int16: 0xd1 + 2 bytes
	data := [u8(0xd1), 0xFF, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 3
}

fn test_msgpack_reader_skip_value_int32() {
	// int32: 0xd2 + 4 bytes
	data := [u8(0xd2), 0x00, 0x00, 0x00, 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_float32() {
	// float32: 0xca + 4 bytes
	data := [u8(0xca), 0x3F, 0x80, 0x00, 0x00]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_uint64() {
	// uint64: 0xcf + 8 bytes
	data := [u8(0xcf), 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 9
}

fn test_msgpack_reader_skip_value_int64() {
	// int64: 0xd3 + 8 bytes
	data := [u8(0xd3), 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 9
}

fn test_msgpack_reader_skip_value_str8() {
	// str8: 0xd9, len=3, "abc"
	data := [u8(0xd9), 0x03, u8(`a`), u8(`b`), u8(`c`)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_str16() {
	// str16: 0xda, len=2 (2 bytes), "ab"
	data := [u8(0xda), 0x00, 0x02, u8(`a`), u8(`b`)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_str32() {
	// str32: 0xdb, len=1 (4 bytes), "x"
	data := [u8(0xdb), 0x00, 0x00, 0x00, 0x01, u8(`x`)]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 6
}

fn test_msgpack_reader_skip_value_bin8() {
	// bin8: 0xc4, len=2, data
	data := [u8(0xc4), 0x02, 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 4
}

fn test_msgpack_reader_skip_value_bin16() {
	// bin16: 0xc5, len=1 (2 bytes), data
	data := [u8(0xc5), 0x00, 0x01, 0xFF]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 4
}

fn test_msgpack_reader_skip_value_bin32() {
	// bin32: 0xc6, len=2 (4 bytes), data
	data := [u8(0xc6), 0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 7
}

fn test_msgpack_reader_skip_value_fixext1() {
	// fixext 1: 0xd4, type + 1 byte
	data := [u8(0xd4), 0x01, 0x42]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 3
}

fn test_msgpack_reader_skip_value_fixext2() {
	// fixext 2: 0xd5, type + 2 bytes
	data := [u8(0xd5), 0x01, 0x42, 0x43]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 4
}

fn test_msgpack_reader_skip_value_fixext4() {
	// fixext 4: 0xd6, type + 4 bytes
	data := [u8(0xd6), 0x01, 0x00, 0x00, 0x00, 0x01]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 6
}

fn test_msgpack_reader_skip_value_fixext8() {
	// fixext 8: 0xd7, type + 8 bytes
	data := [u8(0xd7), 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 10
}

fn test_msgpack_reader_skip_value_fixext16() {
	// fixext 16: 0xd8, type + 16 bytes
	mut data := [u8(0xd8), 0x01]
	for _ in 0 .. 16 {
		data << 0x00
	}
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 18
}

fn test_msgpack_reader_skip_value_array16() {
	// array16: 0xdc, count=2, two fixints
	data := [u8(0xdc), 0x00, 0x02, 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_array32() {
	// array32: 0xdd, count=1, one fixint
	data := [u8(0xdd), 0x00, 0x00, 0x00, 0x01, 0x42]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 6
}

fn test_msgpack_reader_skip_value_map16() {
	// map16: 0xde, count=1, key-value pair (two fixints)
	data := [u8(0xde), 0x00, 0x01, 0x01, 0x02]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 5
}

fn test_msgpack_reader_skip_value_map32() {
	// map32: 0xdf, count=1, key-value pair (two fixints)
	data := [u8(0xdf), 0x00, 0x00, 0x00, 0x01, 0x03, 0x04]
	mut r := MsgpackReader{
		data: data
	}
	r.skip_value()!
	assert r.pos == 7
}

fn test_msgpack_reader_skip_value_empty() {
	data := []u8{}
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.skip_value() {
		assert false, 'expected error on empty data'
	}
}

// ---- read_string edge cases ----

fn test_msgpack_reader_read_string_invalid_type() {
	data := [u8(0xcc)] // uint8, not a string
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_string() {
		assert false, 'expected error for non-string type'
	}
}

fn test_msgpack_reader_read_string_truncated() {
	// fixstr with len 5 but only 2 bytes of data
	data := [u8(0xa5), u8(`a`), u8(`b`)]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_string() {
		assert false, 'expected error for truncated string data'
	}
}

fn test_msgpack_reader_read_string_empty_fixstr() {
	// fixstr with len 0
	data := [u8(0xa0)]
	mut r := MsgpackReader{
		data: data
	}
	s := r.read_string()!
	assert s == ''
}

// ---- read_u16 truncated ----

fn test_msgpack_reader_read_u16_truncated() {
	data := [u8(0x01)]
	mut r := MsgpackReader{
		data: data
	}
	if _ := r.read_u16() {
		assert false, 'expected error for truncated u16'
	}
}

// ---- Fluent protocol message decoding ----

fn test_decode_fluent_message_array_too_short() {
	// fixarray(1) with just a string - array too short
	mut data := []u8{}
	data << 0x91 // fixarray 1
	data << 0xa3 // fixstr "abc"
	data << 'abc'.bytes()
	if _ := decode_fluent_message(data) {
		assert false, 'expected error for array too short'
	}
}

fn test_decode_fluent_message_packed_forward() {
	// PackedForward: [tag, packed_bin]
	// packed_bin contains encoded entries
	mut packed := []u8{}
	// Entry 1: [ts=1, {"k":"v"}]
	packed << 0x92 // fixarray 2
	packed << 0x01 // timestamp 1
	packed << 0x81 // fixmap 1
	packed << 0xa1 // fixstr "k"
	packed << u8(`k`)
	packed << 0xa1 // fixstr "v"
	packed << u8(`v`)

	// Build the full message: [tag, packed_bin]
	mut data := []u8{}
	data << 0x93 // fixarray 3 (PackedForward with no options -- wait, needs to detect bin/str)
	// tag
	data << 0xa4 // fixstr "test"
	data << 'test'.bytes()
	// packed binary using bin8
	data << 0xc4 // bin8
	data << u8(packed.len)
	data << packed

	result := decode_fluent_message(data)!
	assert result.events.len == 1
}

fn test_decode_fluent_message_with_options() {
	// MessageWithOptions: [tag, timestamp, record, options]
	mut data := []u8{}
	data << 0x94 // fixarray 4
	// tag
	data << 0xa4 // fixstr "test"
	data << 'test'.bytes()
	// timestamp: positive fixint 10
	data << 0x0A
	// record: {"msg": "hi"}
	data << 0x81 // fixmap 1
	data << 0xa3 // fixstr "msg"
	data << 'msg'.bytes()
	data << 0xa2 // fixstr "hi"
	data << 'hi'.bytes()
	// options: {"chunk": "abc123"}
	data << 0x81 // fixmap 1
	data << 0xa5 // fixstr "chunk"
	data << 'chunk'.bytes()
	data << 0xa6 // fixstr "abc123"
	data << 'abc123'.bytes()

	result := decode_fluent_message(data)!
	assert result.events.len == 1
	assert result.chunk == 'abc123'
}

fn test_decode_fluent_forward_entry_too_short() {
	// Forward: [tag, [[ts], ...]] - entry has only 1 element
	mut data := []u8{}
	data << 0x92 // fixarray 2
	data << 0xa3 // fixstr "tag"
	data << 'tag'.bytes()
	// entries array
	data << 0x91 // fixarray 1 (one entry)
	data << 0x91 // fixarray 1 (entry with only 1 element - too short)
	data << 0x01 // timestamp 1 (but no record)

	if _ := decode_fluent_message(data) {
		assert false, 'expected error for forward entry too short'
	}
}

fn test_decode_fluent_unsupported_format() {
	// Array of 5 elements - unsupported
	mut data := []u8{}
	data << 0x95 // fixarray 5
	data << 0xa1 // fixstr "t"
	data << u8(`t`)
	data << 0x01
	data << 0x02
	data << 0x03
	data << 0x04

	if _ := decode_fluent_message(data) {
		assert false, 'expected error for unsupported format'
	}
}

fn test_decode_packed_entries_multiple() {
	// Two entries packed
	mut packed := []u8{}
	// Entry 1: [ts=5, {"a":"1"}]
	packed << 0x92
	packed << 0x05
	packed << 0x81
	packed << 0xa1
	packed << u8(`a`)
	packed << 0xa1
	packed << u8(`1`)
	// Entry 2: [ts=10, {"b":"2"}]
	packed << 0x92
	packed << 0x0A
	packed << 0x81
	packed << 0xa1
	packed << u8(`b`)
	packed << 0xa1
	packed << u8(`2`)

	events := decode_packed_entries('test.packed', packed)
	assert events.len == 2
}

fn test_decode_packed_entries_invalid_data() {
	// Invalid packed data - should gracefully return empty
	packed := [u8(0xFF)] // not a valid array start
	events := decode_packed_entries('test.bad', packed)
	assert events.len == 0
}

fn test_decode_packed_entries_entry_too_short() {
	// Entry with array len 1 (too short, need at least 2)
	mut packed := []u8{}
	packed << 0x91 // fixarray 1
	packed << 0x01
	events := decode_packed_entries('test.short', packed)
	assert events.len == 0
}

fn test_decode_packed_entries_empty() {
	events := decode_packed_entries('test.empty', []u8{})
	assert events.len == 0
}

// ---- encode_msgpack_ack coverage ----

fn test_encode_msgpack_ack_long_chunk() {
	// String >= 256 chars to trigger str16 encoding
	chunk := 'x'.repeat(300)
	ack := encode_msgpack_ack(chunk)
	assert ack[0] == 0x81
	// After "ack" key (4 bytes: 0xa3, a, c, k), value should use 0xda (str16)
	assert ack[5] == 0xda
	assert ack.len == 4 + 1 + 1 + 2 + 300 // key(4) + fixmap(1) + str16_header(1) + len(2) + data
}

// ---- record_to_event coverage ----

fn test_record_to_event_zero_timestamp() {
	// When ts is 0, no timestamp field should be set
	ev := record_to_event('test', 0, {
		'key': 'value'
	})
	_ = ev.fields['key'] or { panic('missing key field') }
	_ = ev.fields['tag'] or { panic('missing tag field') }
	assert ev.fields.len >= 2
	// timestamp field should not be present when ts == 0
	if _ := ev.fields['timestamp'] {
		assert false, 'timestamp should not be set when ts is 0'
	}
}

fn test_record_to_event_with_timestamp() {
	ev := record_to_event('mytag', 1000, {
		'msg': 'hello'
	})
	_ = ev.fields['tag'] or { panic('missing tag field') }
	_ = ev.fields['msg'] or { panic('missing msg field') }
	// Timestamp should be present
	_ = ev.fields['timestamp'] or { panic('timestamp should be set') }
	assert ev.fields.len >= 3
}

fn test_record_to_event_empty_record() {
	ev := record_to_event('t', 1, map[string]string{})
	_ = ev.fields['tag'] or { panic('missing tag field') }
	assert ev.meta.source_type == 'fluent'
}

// ---- get_chunk_from_options ----

fn test_get_chunk_from_options_present() {
	opts := {
		'chunk': 'my-chunk-id'
	}
	assert get_chunk_from_options(opts) == 'my-chunk-id'
}

fn test_get_chunk_from_options_absent() {
	opts := {
		'other': 'value'
	}
	assert get_chunk_from_options(opts) == ''
}

fn test_get_chunk_from_options_empty() {
	assert get_chunk_from_options(map[string]string{}) == ''
}

// ---- is_msgpack_int_or_ext / is_msgpack_bin_or_str additional coverage ----

fn test_is_msgpack_int_or_ext_int_types() {
	// int8
	assert is_msgpack_int_or_ext(0xd0) == true
	// int16
	assert is_msgpack_int_or_ext(0xd1) == true
	// int32
	assert is_msgpack_int_or_ext(0xd2) == true
	// int64
	assert is_msgpack_int_or_ext(0xd3) == true
	// uint16
	assert is_msgpack_int_or_ext(0xcd) == true
	// fixext types
	assert is_msgpack_int_or_ext(0xd4) == true
	assert is_msgpack_int_or_ext(0xd5) == true
	assert is_msgpack_int_or_ext(0xd6) == true
	assert is_msgpack_int_or_ext(0xd8) == true
	// map/array should not match
	assert is_msgpack_int_or_ext(0x90) == false
	assert is_msgpack_int_or_ext(0x80) == false
}

fn test_is_msgpack_bin_or_str_boundaries() {
	// Just below fixstr range
	assert is_msgpack_bin_or_str(0x9F) == false
	// In fixstr range
	assert is_msgpack_bin_or_str(0xA5) == true
	// Between ranges - not bin or str
	assert is_msgpack_bin_or_str(0xC0) == false
	assert is_msgpack_bin_or_str(0xC3) == false
}

// ---- Multiple entries in read_map with various value types ----

fn test_msgpack_reader_read_map_with_int_values() {
	// fixmap(2): {"count": uint8(42), "flag": true}
	mut data := []u8{}
	data << 0x82 // fixmap 2
	// key "count"
	data << 0xa5
	data << 'count'.bytes()
	// value: uint8 42
	data << 0xcc
	data << 0x2A
	// key "flag"
	data << 0xa4
	data << 'flag'.bytes()
	// value: true
	data << 0xc3

	mut r := MsgpackReader{
		data: data
	}
	m := r.read_map()!
	assert m.len == 2
	assert m['count'] == '42'
	assert m['flag'] == 'true'
}
