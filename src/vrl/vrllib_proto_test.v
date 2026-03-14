module vrl

// Tests for vrllib_proto.v - protobuf encoding/decoding internals

// === Varint tests ===

fn test_proto_decode_varint_simple() {
	data := [u8(0x08)] // varint 8
	val, pos := proto_decode_varint(data, 0) or {
		assert false, 'decode varint simple: ${err}'
		return
	}
	assert val == 8
	assert pos == 1
}

fn test_proto_decode_varint_multibyte() {
	data := [u8(0xAC), u8(0x02)] // varint 300
	val, pos := proto_decode_varint(data, 0) or {
		assert false, 'decode varint multi: ${err}'
		return
	}
	assert val == 300
	assert pos == 2
}

fn test_proto_decode_varint_zero() {
	data := [u8(0x00)]
	val, _ := proto_decode_varint(data, 0) or {
		assert false, 'decode varint zero: ${err}'
		return
	}
	assert val == 0
}

fn test_proto_decode_varint_truncated() {
	data := [u8(0x80)] // continuation bit set but no more bytes
	proto_decode_varint(data, 0) or {
		assert err.msg().contains('unexpected end')
		return
	}
	assert false, 'expected error'
}

fn test_proto_encode_varint_simple() {
	result := proto_encode_varint(u64(8))
	assert result == [u8(0x08)]
}

fn test_proto_encode_varint_multibyte() {
	result := proto_encode_varint(u64(300))
	assert result == [u8(0xAC), u8(0x02)]
}

fn test_proto_encode_varint_zero() {
	result := proto_encode_varint(u64(0))
	assert result == [u8(0x00)]
}

fn test_proto_encode_varint_large() {
	result := proto_encode_varint(u64(0xFFFFFFFF))
	assert result.len > 1
	// Verify roundtrip
	decoded, _ := proto_decode_varint(result, 0) or {
		assert false, 'roundtrip: ${err}'
		return
	}
	assert decoded == 0xFFFFFFFF
}

// === Zigzag tests ===

fn test_proto_zigzag_decode_32() {
	assert proto_zigzag_decode_32(0) == 0
	assert proto_zigzag_decode_32(1) == -1
	assert proto_zigzag_decode_32(2) == 1
	assert proto_zigzag_decode_32(3) == -2
}

fn test_proto_zigzag_decode_64() {
	assert proto_zigzag_decode_64(0) == 0
	assert proto_zigzag_decode_64(1) == -1
	assert proto_zigzag_decode_64(2) == 1
	assert proto_zigzag_decode_64(3) == -2
}

fn test_proto_zigzag_encode_32() {
	assert proto_zigzag_encode_32(0) == 0
	assert proto_zigzag_encode_32(-1) == 1
	assert proto_zigzag_encode_32(1) == 2
	assert proto_zigzag_encode_32(-2) == 3
}

fn test_proto_zigzag_encode_64() {
	assert proto_zigzag_encode_64(0) == 0
	assert proto_zigzag_encode_64(-1) == 1
	assert proto_zigzag_encode_64(1) == 2
	assert proto_zigzag_encode_64(-2) == 3
}

fn test_proto_zigzag_roundtrip_32() {
	for v in [i32(0), 1, -1, 127, -128, 32767, -32768] {
		assert proto_zigzag_decode_32(proto_zigzag_encode_32(v)) == v
	}
}

fn test_proto_zigzag_roundtrip_64() {
	for v in [i64(0), 1, -1, 127, -128, 32767, -32768, 2147483647, -2147483648] {
		assert proto_zigzag_decode_64(proto_zigzag_encode_64(v)) == v
	}
}

// === Skip field tests ===

fn test_proto_skip_field_varint() {
	data := [u8(0x08)] // varint 8
	pos := proto_skip_field(data, 0, wire_varint) or {
		assert false, 'skip varint: ${err}'
		return
	}
	assert pos == 1
}

fn test_proto_skip_field_64bit() {
	data := [u8(0), 0, 0, 0, 0, 0, 0, 0]
	pos := proto_skip_field(data, 0, wire_64bit) or {
		assert false, 'skip 64bit: ${err}'
		return
	}
	assert pos == 8
}

fn test_proto_skip_field_32bit() {
	data := [u8(0), 0, 0, 0]
	pos := proto_skip_field(data, 0, wire_32bit) or {
		assert false, 'skip 32bit: ${err}'
		return
	}
	assert pos == 4
}

fn test_proto_skip_field_length_delimited() {
	data := [u8(0x03), u8(`a`), u8(`b`), u8(`c`)] // length 3 + "abc"
	pos := proto_skip_field(data, 0, wire_length_delimited) or {
		assert false, 'skip ld: ${err}'
		return
	}
	assert pos == 4
}

fn test_proto_skip_field_unknown_wire() {
	proto_skip_field([]u8{}, 0, 6) or {
		assert err.msg().contains('unknown wire type')
		return
	}
	assert false, 'expected error'
}

fn test_proto_skip_field_truncated_64bit() {
	data := [u8(0), 0, 0] // only 3 bytes, need 8
	proto_skip_field(data, 0, wire_64bit) or {
		assert err.msg().contains('truncated')
		return
	}
	assert false, 'expected error'
}

fn test_proto_skip_field_truncated_32bit() {
	data := [u8(0)] // only 1 byte, need 4
	proto_skip_field(data, 0, wire_32bit) or {
		assert err.msg().contains('truncated')
		return
	}
	assert false, 'expected error'
}

// === Message encoding/decoding roundtrip ===

fn test_proto_encode_decode_simple_message() {
	// Create a simple message descriptor
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Simple'
		fields: [
			ProtoFieldDescriptor{
				name: 'name'
				number: 1
				field_type: proto_type_string
				label: 1
			},
			ProtoFieldDescriptor{
				name: 'id'
				number: 2
				field_type: proto_type_int32
				label: 1
			},
			ProtoFieldDescriptor{
				name: 'active'
				number: 3
				field_type: proto_type_bool
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{
		messages: [msg_desc]
	}

	// Build an object to encode
	mut obj := new_object_map()
	obj.set('name', VrlValue('hello'))
	obj.set('id', VrlValue(i64(42)))
	obj.set('active', VrlValue(true))

	// Encode
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode: ${err}'
		return
	}
	assert encoded.len > 0

	// Decode
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode: ${err}'
		return
	}
	decoded_obj := decoded as ObjectMap
	name_val := decoded_obj.get('name') or {
		assert false, 'no name'
		return
	}
	assert (name_val as string) == 'hello'
	id_val := decoded_obj.get('id') or {
		assert false, 'no id'
		return
	}
	assert (id_val as i64) == 42
	active_val := decoded_obj.get('active') or {
		assert false, 'no active'
		return
	}
	assert (active_val as bool) == true
}

fn test_proto_encode_decode_double() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.DoubleMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_double
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(f64(3.14)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode double: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode double: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	f := v as f64
	assert f > 3.13 && f < 3.15
}

fn test_proto_encode_decode_float() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.FloatMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_float
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(f64(1.5)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode float: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode float: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	f := v as f64
	assert f > 1.4 && f < 1.6
}

fn test_proto_encode_decode_fixed64() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Fixed64Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_fixed64
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(999)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode fixed64: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode fixed64: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	assert (v as i64) == 999
}

fn test_proto_encode_decode_fixed32() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Fixed32Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_fixed32
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(42)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode fixed32: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode fixed32: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	assert (v as i64) == 42
}

fn test_proto_encode_decode_sfixed64() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.SFixed64Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_sfixed64
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(-100)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode sfixed64: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode sfixed64: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	assert (v as i64) == -100
}

fn test_proto_encode_decode_sfixed32() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.SFixed32Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_sfixed32
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(-42)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode sfixed32: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode sfixed32: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	// sfixed32 decode: i64(i32(raw.fixed32))
	// sfixed32 encode: u32(val as i64)
	// -42 as u32 wraps, then back as i32 should give -42
	assert (v as i64) == -42
}

fn test_proto_encode_decode_sint32() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Sint32Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_sint32
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(-7)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode sint32: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode sint32: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	assert (v as i64) == -7
}

fn test_proto_encode_decode_sint64() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Sint64Msg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_sint64
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(-999)))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode sint64: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode sint64: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('value') or {
		assert false, 'no value'
		return
	}
	assert (v as i64) == -999
}

fn test_proto_encode_decode_bytes() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.BytesMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'data'
				number: 1
				field_type: proto_type_bytes
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('data', VrlValue('\x01\x02\x03'))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode bytes: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode bytes: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('data') or {
		assert false, 'no data'
		return
	}
	assert (v as string) == '\x01\x02\x03'
}

fn test_proto_encode_decode_repeated() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.RepeatedMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'items'
				number: 1
				field_type: proto_type_string
				label: 3 // repeated
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('items', VrlValue([VrlValue('a'), VrlValue('b'), VrlValue('c')]))

	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode repeated: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode repeated: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('items') or {
		assert false, 'no items'
		return
	}
	arr := v as []VrlValue
	assert arr.len == 3
}

fn test_proto_encode_decode_nested_message() {
	inner_desc := ProtoMessageDescriptor{
		full_name: 'test.Inner'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_string
				label: 1
			},
		]
	}
	outer_desc := ProtoMessageDescriptor{
		full_name: 'test.Outer'
		fields: [
			ProtoFieldDescriptor{
				name: 'inner'
				number: 1
				field_type: proto_type_message
				type_name: 'test.Inner'
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{
		messages: [outer_desc, inner_desc]
	}

	mut inner_obj := new_object_map()
	inner_obj.set('value', VrlValue('nested'))
	mut outer_obj := new_object_map()
	outer_obj.set('inner', VrlValue(inner_obj))

	encoded := proto_encode_message(outer_obj, outer_desc, descs) or {
		assert false, 'encode nested: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, outer_desc, descs) or {
		assert false, 'decode nested: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	inner_val := result_obj.get('inner') or {
		assert false, 'no inner'
		return
	}
	inner_result := inner_val as ObjectMap
	v := inner_result.get('value') or {
		assert false, 'no value in inner'
		return
	}
	assert (v as string) == 'nested'
}

fn test_proto_encode_decode_enum() {
	enum_desc := ProtoEnumDescriptor{
		name: 'test.Status'
		values: [
			ProtoEnumValue{name: 'UNKNOWN', number: 0},
			ProtoEnumValue{name: 'ACTIVE', number: 1},
			ProtoEnumValue{name: 'INACTIVE', number: 2},
		]
	}
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.EnumMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'status'
				number: 1
				field_type: proto_type_enum
				type_name: 'test.Status'
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{
		messages: [msg_desc]
		enums: [enum_desc]
	}

	// Encode with string value
	mut obj := new_object_map()
	obj.set('status', VrlValue('ACTIVE'))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode enum: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode enum: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('status') or {
		assert false, 'no status'
		return
	}
	assert (v as string) == 'ACTIVE'
}

fn test_proto_encode_decode_enum_int() {
	enum_desc := ProtoEnumDescriptor{
		name: 'test.Color'
		values: [
			ProtoEnumValue{name: 'RED', number: 0},
			ProtoEnumValue{name: 'GREEN', number: 1},
		]
	}
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.ColorMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'color'
				number: 1
				field_type: proto_type_enum
				type_name: 'test.Color'
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{
		messages: [msg_desc]
		enums: [enum_desc]
	}

	// Encode with integer value
	mut obj := new_object_map()
	obj.set('color', VrlValue(i64(1)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode enum int: ${err}'
		return
	}
	decoded := proto_decode_message(encoded, msg_desc, descs) or {
		assert false, 'decode enum int: ${err}'
		return
	}
	result_obj := decoded as ObjectMap
	v := result_obj.get('color') or {
		assert false, 'no color'
		return
	}
	assert (v as string) == 'GREEN'
}

fn test_proto_find_message_with_dot_prefix() {
	msg := ProtoMessageDescriptor{full_name: 'test.Msg'}
	descs := ProtoFileDescriptors{messages: [msg]}
	found := proto_find_message(descs, '.test.Msg') or {
		assert false, 'find msg with dot: ${err}'
		return
	}
	assert found.full_name == 'test.Msg'
}

fn test_proto_find_message_not_found() {
	descs := ProtoFileDescriptors{messages: []}
	proto_find_message(descs, 'nonexistent') or {
		assert err.msg().contains('not found')
		return
	}
	assert false, 'expected error'
}

fn test_proto_find_enum() {
	enum_desc := ProtoEnumDescriptor{
		name: 'test.Status'
		values: [ProtoEnumValue{name: 'OK', number: 0}]
	}
	descs := ProtoFileDescriptors{enums: [enum_desc]}
	if found := proto_find_enum(descs, 'test.Status') {
		assert found.name == 'test.Status'
	} else {
		assert false, 'should find enum'
	}
}

fn test_proto_find_enum_not_found() {
	descs := ProtoFileDescriptors{}
	if _ := proto_find_enum(descs, 'nonexistent') {
		assert false, 'should not find'
	}
}

fn test_proto_find_enum_in_message() {
	enum_desc := ProtoEnumDescriptor{
		name: 'test.Msg.InnerEnum'
		values: [ProtoEnumValue{name: 'A', number: 0}]
	}
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.Msg'
		enum_types: [enum_desc]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}
	if found := proto_find_enum(descs, 'test.Msg.InnerEnum') {
		assert found.name == 'test.Msg.InnerEnum'
	} else {
		assert false, 'should find nested enum'
	}
}

fn test_proto_find_nested_message() {
	inner := ProtoMessageDescriptor{full_name: 'test.Outer.Inner'}
	outer := ProtoMessageDescriptor{
		full_name: 'test.Outer'
		nested_types: [inner]
	}
	descs := ProtoFileDescriptors{messages: [outer]}
	found := proto_find_message(descs, 'test.Outer.Inner') or {
		assert false, 'find nested: ${err}'
		return
	}
	assert found.full_name == 'test.Outer.Inner'
}

fn test_proto_is_packable_type() {
	assert proto_is_packable_type(proto_type_int32) == true
	assert proto_is_packable_type(proto_type_double) == true
	assert proto_is_packable_type(proto_type_bool) == true
	assert proto_is_packable_type(proto_type_string) == false
	assert proto_is_packable_type(proto_type_message) == false
}

fn test_proto_decode_packed_varint() {
	// Pack two varints: 1 and 2
	data := [u8(1), u8(2)]
	result := proto_decode_packed(data, proto_type_int32) or {
		assert false, 'packed varint: ${err}'
		return
	}
	assert result.len == 2
	assert (result[0] as i64) == 1
	assert (result[1] as i64) == 2
}

fn test_proto_decode_packed_bool() {
	data := [u8(1), u8(0), u8(1)]
	result := proto_decode_packed(data, proto_type_bool) or {
		assert false, 'packed bool: ${err}'
		return
	}
	assert result.len == 3
	assert (result[0] as bool) == true
	assert (result[1] as bool) == false
}

fn test_proto_decode_packed_sint32() {
	// zigzag encoded: -1 -> 1, 1 -> 2
	data := [u8(1), u8(2)]
	result := proto_decode_packed(data, proto_type_sint32) or {
		assert false, 'packed sint32: ${err}'
		return
	}
	assert result.len == 2
	assert (result[0] as i64) == -1
	assert (result[1] as i64) == 1
}

fn test_proto_decode_packed_sint64() {
	data := [u8(1), u8(2)]
	result := proto_decode_packed(data, proto_type_sint64) or {
		assert false, 'packed sint64: ${err}'
		return
	}
	assert result.len == 2
	assert (result[0] as i64) == -1
	assert (result[1] as i64) == 1
}

fn test_proto_decode_packed_enum() {
	data := [u8(0), u8(1), u8(2)]
	result := proto_decode_packed(data, proto_type_enum) or {
		assert false, 'packed enum: ${err}'
		return
	}
	assert result.len == 3
}

fn test_proto_decode_packed_fixed32() {
	// Two fixed32 values: 1 and 2
	mut data := []u8{len: 8}
	data[0] = 1 // little-endian 1
	data[4] = 2 // little-endian 2
	result := proto_decode_packed(data, proto_type_fixed32) or {
		assert false, 'packed fixed32: ${err}'
		return
	}
	assert result.len == 2
	assert (result[0] as i64) == 1
	assert (result[1] as i64) == 2
}

fn test_proto_decode_packed_sfixed32() {
	mut data := []u8{len: 4}
	// -1 in little-endian u32 = 0xFFFFFFFF
	data[0] = 0xFF
	data[1] = 0xFF
	data[2] = 0xFF
	data[3] = 0xFF
	result := proto_decode_packed(data, proto_type_sfixed32) or {
		assert false, 'packed sfixed32: ${err}'
		return
	}
	assert result.len == 1
	assert (result[0] as i64) == -1
}

fn test_proto_decode_packed_fixed64() {
	mut data := []u8{len: 8}
	data[0] = 42
	result := proto_decode_packed(data, proto_type_fixed64) or {
		assert false, 'packed fixed64: ${err}'
		return
	}
	assert result.len == 1
	assert (result[0] as i64) == 42
}

fn test_proto_decode_packed_sfixed64() {
	mut data := []u8{len: 8}
	for i in 0 .. 8 {
		data[i] = 0xFF
	}
	result := proto_decode_packed(data, proto_type_sfixed64) or {
		assert false, 'packed sfixed64: ${err}'
		return
	}
	assert result.len == 1
	assert (result[0] as i64) == -1
}

fn test_proto_decode_packed_double() {
	// 8 bytes for a double 0.0
	data := []u8{len: 8}
	result := proto_decode_packed(data, proto_type_double) or {
		assert false, 'packed double: ${err}'
		return
	}
	assert result.len == 1
}

fn test_proto_decode_packed_float() {
	// 4 bytes for a float 0.0
	data := []u8{len: 4}
	result := proto_decode_packed(data, proto_type_float) or {
		assert false, 'packed float: ${err}'
		return
	}
	assert result.len == 1
}

fn test_proto_encode_string_from_int() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.StrMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_string
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	// String field with i64 input
	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(42)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode str from int: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_string_from_bool() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.StrMsg2'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_string
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(true))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode str from bool: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_int_from_string() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.IntMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_int32
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue('42'))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode int from str: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_int_from_f64() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.IntMsg2'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_int32
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(f64(42.0)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode int from f64: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_double_from_int() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.DoubleMsg2'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_double
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(42)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode double from int: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_float_from_int() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.FloatMsg2'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_float
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(i64(42)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode float from int: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_encode_null_skip() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.NullMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_string
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(VrlNull{}))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode null: ${err}'
		return
	}
	assert encoded.len == 0 // null values are skipped
}

fn test_proto_encode_json_name_fallback() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.JsonMsg'
		fields: [
			ProtoFieldDescriptor{
				name: 'some_field'
				number: 1
				field_type: proto_type_string
				label: 1
				json_name: 'someField'
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('someField', VrlValue('hello'))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode json name: ${err}'
		return
	}
	assert encoded.len > 0
}

fn test_proto_string_from_f64() {
	msg_desc := ProtoMessageDescriptor{
		full_name: 'test.StrMsg3'
		fields: [
			ProtoFieldDescriptor{
				name: 'value'
				number: 1
				field_type: proto_type_string
				label: 1
			},
		]
	}
	descs := ProtoFileDescriptors{messages: [msg_desc]}

	mut obj := new_object_map()
	obj.set('value', VrlValue(f64(3.14)))
	encoded := proto_encode_message(obj, msg_desc, descs) or {
		assert false, 'encode str from f64: ${err}'
		return
	}
	assert encoded.len > 0
}

// Test fn_parse_proto and fn_encode_proto error paths

fn test_fn_parse_proto_too_few_args() {
	fn_parse_proto([VrlValue('data'), VrlValue('file')]) or {
		assert err.msg().contains('requires 3')
		return
	}
	assert false, 'expected error'
}

fn test_fn_parse_proto_bad_value_type() {
	fn_parse_proto([VrlValue(i64(1)), VrlValue('file'), VrlValue('type')]) or {
		assert err.msg().contains('must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_fn_parse_proto_bad_desc_type() {
	fn_parse_proto([VrlValue('data'), VrlValue(i64(1)), VrlValue('type')]) or {
		assert err.msg().contains('desc_file must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_fn_parse_proto_bad_msg_type() {
	fn_parse_proto([VrlValue('data'), VrlValue('file'), VrlValue(i64(1))]) or {
		assert err.msg().contains('message_type must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_fn_parse_proto_missing_file() {
	fn_parse_proto([VrlValue('data'), VrlValue('/nonexistent/file.desc'), VrlValue('Test')]) or {
		assert err.msg().contains('failed to open')
		return
	}
	assert false, 'expected error'
}

fn test_fn_encode_proto_too_few_args() {
	fn_encode_proto([VrlValue('data'), VrlValue('file')]) or {
		assert err.msg().contains('requires 3')
		return
	}
	assert false, 'expected error'
}

fn test_fn_encode_proto_bad_desc_type() {
	fn_encode_proto([VrlValue(new_object_map()), VrlValue(i64(1)), VrlValue('type')]) or {
		assert err.msg().contains('desc_file must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_fn_encode_proto_bad_msg_type() {
	fn_encode_proto([VrlValue(new_object_map()), VrlValue('file'), VrlValue(i64(1))]) or {
		assert err.msg().contains('message_type must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_fn_encode_proto_bad_value_type() {
	fn_encode_proto([VrlValue('not_obj'), VrlValue('/nonexistent'), VrlValue('T')]) or {
		// Will fail on file open first
		return
	}
}

fn test_fn_encode_proto_missing_file() {
	fn_encode_proto([VrlValue(new_object_map()), VrlValue('/nonexistent/file.desc'), VrlValue('Test')]) or {
		assert err.msg().contains('failed to open')
		return
	}
	assert false, 'expected error'
}

// Test FileDescriptorSet parsing with hand-crafted bytes
fn test_proto_parse_file_descriptor_set_empty() {
	result := proto_parse_file_descriptor_set([]u8{}) or {
		assert false, 'parse empty fds: ${err}'
		return
	}
	assert result.messages.len == 0
	assert result.enums.len == 0
}

fn test_proto_parse_file_descriptor_set_truncated() {
	// A tag saying field 1, wire type 2 (length-delimited) but truncated length
	data := [u8(0x0A), u8(0xFF), u8(0xFF), u8(0xFF), u8(0x7F)] // field 1, huge length
	proto_parse_file_descriptor_set(data) or {
		assert err.msg().contains('truncated')
		return
	}
	assert false, 'expected error'
}
