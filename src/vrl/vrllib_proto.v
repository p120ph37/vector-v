module vrl

import os

// Protobuf wire types
const wire_varint = 0
const wire_64bit = 1
const wire_length_delimited = 2
const wire_32bit = 5

// parse_proto(value, desc_file, message_type)
// Parses a protobuf binary payload using a .desc descriptor file.
// Returns an object matching the protobuf message schema.
fn fn_parse_proto(args []VrlValue) !VrlValue {
	if args.len < 3 {
		return error('parse_proto requires 3 arguments')
	}
	payload := match args[0] {
		string { args[0] as string }
		else { return error('parse_proto: value must be a string (bytes)') }
	}
	desc_file := match args[1] {
		string { args[1] as string }
		else { return error('parse_proto: desc_file must be a string') }
	}
	message_type := match args[2] {
		string { args[2] as string }
		else { return error('parse_proto: message_type must be a string') }
	}

	// Load and parse the descriptor file
	desc_bytes := os.read_bytes(desc_file) or {
		return error('parse_proto: failed to open descriptor file: ${desc_file}')
	}

	// Parse the FileDescriptorSet from the descriptor bytes
	descriptors := proto_parse_file_descriptor_set(desc_bytes) or {
		return error('parse_proto: failed to parse descriptor file: ${err.msg()}')
	}

	// Find the message descriptor
	msg_desc := proto_find_message(descriptors, message_type) or {
		return error("parse_proto: message type '${message_type}' not found in descriptor")
	}

	// Parse the payload using the descriptor
	result := proto_decode_message(payload.bytes(), msg_desc, descriptors) or {
		return error('parse_proto: error parsing protobuf: ${err.msg()}')
	}

	return result
}

// encode_proto(value, desc_file, message_type)
// Encodes a VRL value into protobuf binary format.
fn fn_encode_proto(args []VrlValue) !VrlValue {
	if args.len < 3 {
		return error('encode_proto requires 3 arguments')
	}
	value := args[0]
	desc_file := match args[1] {
		string { args[1] as string }
		else { return error('encode_proto: desc_file must be a string') }
	}
	message_type := match args[2] {
		string { args[2] as string }
		else { return error('encode_proto: message_type must be a string') }
	}

	desc_bytes := os.read_bytes(desc_file) or {
		return error('encode_proto: failed to open descriptor file: ${desc_file}')
	}

	descriptors := proto_parse_file_descriptor_set(desc_bytes) or {
		return error('encode_proto: failed to parse descriptor file: ${err.msg()}')
	}

	msg_desc := proto_find_message(descriptors, message_type) or {
		return error("encode_proto: message type '${message_type}' not found in descriptor")
	}

	obj := match value {
		ObjectMap { value }
		else { return error('encode_proto: value must be an object') }
	}

	result := proto_encode_message(obj, msg_desc, descriptors) or {
		return error('encode_proto: error encoding protobuf: ${err.msg()}')
	}

	return VrlValue(result.bytestr())
}

// --- Protobuf descriptor structures ---
// These represent the minimal subset of FileDescriptorSet/FileDescriptorProto/DescriptorProto
// needed to parse and encode protobuf messages.

struct ProtoFieldDescriptor {
	name       string
	number     int
	field_type int // protobuf field type enum
	type_name  string // for message/enum references
	label      int // 1=optional, 2=required, 3=repeated
	json_name  string
}

struct ProtoEnumValue {
	name   string
	number int
}

struct ProtoEnumDescriptor {
	name   string
	values []ProtoEnumValue
}

struct ProtoMessageDescriptor {
	full_name    string
	fields       []ProtoFieldDescriptor
	nested_types []ProtoMessageDescriptor
	enum_types   []ProtoEnumDescriptor
}

struct ProtoFileDescriptors {
	messages []ProtoMessageDescriptor
	enums    []ProtoEnumDescriptor
}

// Protobuf field type constants (from google/protobuf/descriptor.proto)
const proto_type_double = 1
const proto_type_float = 2
const proto_type_int64 = 3
const proto_type_uint64 = 4
const proto_type_int32 = 5
const proto_type_fixed64 = 6
const proto_type_fixed32 = 7
const proto_type_bool = 8
const proto_type_string = 9
const proto_type_group = 10
const proto_type_message = 11
const proto_type_bytes = 12
const proto_type_uint32 = 13
const proto_type_enum = 14
const proto_type_sfixed32 = 15
const proto_type_sfixed64 = 16
const proto_type_sint32 = 17
const proto_type_sint64 = 18

// --- Protobuf varint decoding ---

fn proto_decode_varint(data []u8, offset int) !(u64, int) {
	mut result := u64(0)
	mut shift := u32(0)
	mut pos := offset
	for pos < data.len {
		b := data[pos]
		result |= u64(b & 0x7F) << shift
		pos++
		if b & 0x80 == 0 {
			return result, pos
		}
		shift += 7
		if shift >= 64 {
			return error('varint too long')
		}
	}
	return error('unexpected end of varint')
}

fn proto_encode_varint(val u64) []u8 {
	mut v := val
	mut result := []u8{}
	for {
		b := u8(v & 0x7F)
		v >>= 7
		if v == 0 {
			result << b
			break
		}
		result << (b | 0x80)
	}
	return result
}

fn proto_zigzag_decode_32(n u32) i32 {
	return i32((n >> 1) ^ (-(n & 1)))
}

fn proto_zigzag_decode_64(n u64) i64 {
	return i64((n >> 1) ^ (-(n & 1)))
}

fn proto_zigzag_encode_32(n i32) u32 {
	return u32((n << 1) ^ (n >> 31))
}

fn proto_zigzag_encode_64(n i64) u64 {
	return u64((n << 1) ^ (n >> 63))
}

// --- FileDescriptorSet parser ---
// Parses a protobuf-encoded FileDescriptorSet (the output of protoc -o).
// This is a minimal self-bootstrapping parser.

fn proto_parse_file_descriptor_set(data []u8) !ProtoFileDescriptors {
	mut messages := []ProtoMessageDescriptor{}
	mut enums := []ProtoEnumDescriptor{}

	// FileDescriptorSet has field 1 = repeated FileDescriptorProto
	mut pos := 0
	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if field_num == 1 && wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated FileDescriptorProto')
			}
			file_msgs, file_enums := proto_parse_file_descriptor_proto(data[pos..end], '')!
			messages << file_msgs
			enums << file_enums
			pos = end
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}
	return ProtoFileDescriptors{
		messages: messages
		enums: enums
	}
}

fn proto_parse_file_descriptor_proto(data []u8, parent_prefix string) !([]ProtoMessageDescriptor, []ProtoEnumDescriptor) {
	mut messages := []ProtoMessageDescriptor{}
	mut enums := []ProtoEnumDescriptor{}
	mut package := ''
	mut pos := 0

	// First pass: extract package name
	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if field_num == 2 && wire_type == wire_length_delimited {
			// package field
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated package name')
			}
			package = data[pos..end].bytestr()
			pos = end
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}

	prefix := if package.len > 0 { '${package}.' } else { parent_prefix }

	// Second pass: parse messages and enums
	pos = 0
	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated field')
			}
			if field_num == 4 {
				// DescriptorProto (message type)
				msg := proto_parse_descriptor_proto(data[pos..end], prefix)!
				messages << msg
			} else if field_num == 5 {
				// EnumDescriptorProto
				e := proto_parse_enum_descriptor_proto(data[pos..end], prefix)!
				enums << e
			}
			pos = end
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}
	return messages, enums
}

fn proto_parse_descriptor_proto(data []u8, prefix string) !ProtoMessageDescriptor {
	mut name := ''
	mut fields := []ProtoFieldDescriptor{}
	mut nested := []ProtoMessageDescriptor{}
	mut enum_types := []ProtoEnumDescriptor{}
	mut pos := 0

	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated field in DescriptorProto')
			}
			match field_num {
				1 {
					// name
					name = data[pos..end].bytestr()
				}
				2 {
					// field
					f := proto_parse_field_descriptor_proto(data[pos..end])!
					fields << f
				}
				3 {
					// nested_type
					full_prefix := '${prefix}${name}.'
					nested_msg := proto_parse_descriptor_proto(data[pos..end], full_prefix)!
					nested << nested_msg
				}
				4 {
					// enum_type
					full_prefix := '${prefix}${name}.'
					e := proto_parse_enum_descriptor_proto(data[pos..end], full_prefix)!
					enum_types << e
				}
				else {}
			}
			pos = end
		} else if wire_type == wire_varint {
			_, vpos := proto_decode_varint(data, pos)!
			pos = vpos
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}

	full_name := '${prefix}${name}'

	mut all_messages := []ProtoMessageDescriptor{}
	all_messages << ProtoMessageDescriptor{
		full_name: full_name
		fields: fields
		nested_types: nested
		enum_types: enum_types
	}
	// Flatten nested types
	for n in nested {
		all_messages << n
	}
	return all_messages[0]
}

fn proto_parse_field_descriptor_proto(data []u8) !ProtoFieldDescriptor {
	mut name := ''
	mut number := 0
	mut field_type := 0
	mut type_name := ''
	mut label := 1
	mut json_name := ''
	mut pos := 0

	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if wire_type == wire_varint {
			val, vpos := proto_decode_varint(data, pos)!
			pos = vpos
			match field_num {
				3 { number = int(val) }
				4 { label = int(val) }
				5 { field_type = int(val) }
				else {}
			}
		} else if wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated field descriptor')
			}
			match field_num {
				1 { name = data[pos..end].bytestr() }
				6 { type_name = data[pos..end].bytestr() }
				10 { json_name = data[pos..end].bytestr() }
				else {}
			}
			pos = end
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}

	return ProtoFieldDescriptor{
		name: name
		number: number
		field_type: field_type
		type_name: type_name
		label: label
		json_name: json_name
	}
}

fn proto_parse_enum_descriptor_proto(data []u8, prefix string) !ProtoEnumDescriptor {
	mut name := ''
	mut values := []ProtoEnumValue{}
	mut pos := 0

	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated enum descriptor')
			}
			if field_num == 1 {
				name = data[pos..end].bytestr()
			} else if field_num == 2 {
				ev := proto_parse_enum_value_descriptor_proto(data[pos..end])!
				values << ev
			}
			pos = end
		} else if wire_type == wire_varint {
			_, vpos := proto_decode_varint(data, pos)!
			pos = vpos
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}

	return ProtoEnumDescriptor{
		name: '${prefix}${name}'
		values: values
	}
}

fn proto_parse_enum_value_descriptor_proto(data []u8) !ProtoEnumValue {
	mut name := ''
	mut number := 0
	mut pos := 0

	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		if wire_type == wire_varint {
			val, vpos := proto_decode_varint(data, pos)!
			pos = vpos
			if field_num == 2 {
				number = int(val)
			}
		} else if wire_type == wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			pos = lpos
			end := pos + int(length)
			if end > data.len {
				return error('truncated enum value')
			}
			if field_num == 1 {
				name = data[pos..end].bytestr()
			}
			pos = end
		} else {
			pos = proto_skip_field(data, pos, wire_type)!
		}
	}

	return ProtoEnumValue{
		name: name
		number: number
	}
}

fn proto_skip_field(data []u8, pos int, wire_type int) !int {
	match wire_type {
		wire_varint {
			_, new_pos := proto_decode_varint(data, pos)!
			return new_pos
		}
		wire_64bit {
			if pos + 8 > data.len {
				return error('truncated 64-bit field')
			}
			return pos + 8
		}
		wire_length_delimited {
			length, lpos := proto_decode_varint(data, pos)!
			end := lpos + int(length)
			if end > data.len {
				return error('truncated length-delimited field')
			}
			return end
		}
		wire_32bit {
			if pos + 4 > data.len {
				return error('truncated 32-bit field')
			}
			return pos + 4
		}
		else {
			return error('unknown wire type: ${wire_type}')
		}
	}
}

fn proto_find_message(descs ProtoFileDescriptors, name string) !ProtoMessageDescriptor {
	// Strip leading dot if present
	search_name := if name.starts_with('.') { name[1..] } else { name }
	for msg in descs.messages {
		if msg.full_name == search_name {
			return msg
		}
		// Search nested types
		if found := proto_find_nested_message(msg, search_name) {
			return found
		}
	}
	return error("message type '${search_name}' not found")
}

fn proto_find_nested_message(msg ProtoMessageDescriptor, name string) ?ProtoMessageDescriptor {
	for nested in msg.nested_types {
		if nested.full_name == name {
			return nested
		}
		if found := proto_find_nested_message(nested, name) {
			return found
		}
	}
	return none
}

fn proto_find_enum(descs ProtoFileDescriptors, name string) ?ProtoEnumDescriptor {
	search_name := if name.starts_with('.') { name[1..] } else { name }
	for e in descs.enums {
		if e.name == search_name {
			return e
		}
	}
	// Also search enums nested in messages
	for msg in descs.messages {
		if found := proto_find_enum_in_message(msg, search_name) {
			return found
		}
	}
	return none
}

fn proto_find_enum_in_message(msg ProtoMessageDescriptor, name string) ?ProtoEnumDescriptor {
	for e in msg.enum_types {
		if e.name == name {
			return e
		}
	}
	for nested in msg.nested_types {
		if found := proto_find_enum_in_message(nested, name) {
			return found
		}
	}
	return none
}

// --- Protobuf message decoding ---

fn proto_decode_message(data []u8, msg_desc ProtoMessageDescriptor, descs ProtoFileDescriptors) !VrlValue {
	// Collect raw field values (field_number -> list of raw bytes/values)
	mut field_values := map[int][]ProtoRawValue{}
	mut pos := 0

	for pos < data.len {
		tag_val, new_pos := proto_decode_varint(data, pos)!
		pos = new_pos
		field_num := int(tag_val >> 3)
		wire_type := int(tag_val & 0x7)

		match wire_type {
			wire_varint {
				val, vpos := proto_decode_varint(data, pos)!
				pos = vpos
				if field_num !in field_values {
					field_values[field_num] = []ProtoRawValue{}
				}
				field_values[field_num] << ProtoRawValue{
					varint: val
					wire_type: wire_varint
				}
			}
			wire_64bit {
				if pos + 8 > data.len {
					return error('truncated 64-bit field')
				}
				mut val := u64(0)
				for i in 0 .. 8 {
					val |= u64(data[pos + i]) << (u32(i) * 8)
				}
				pos += 8
				if field_num !in field_values {
					field_values[field_num] = []ProtoRawValue{}
				}
				field_values[field_num] << ProtoRawValue{
					fixed64: val
					wire_type: wire_64bit
				}
			}
			wire_length_delimited {
				length, lpos := proto_decode_varint(data, pos)!
				pos = lpos
				end := pos + int(length)
				if end > data.len {
					return error('truncated length-delimited field')
				}
				if field_num !in field_values {
					field_values[field_num] = []ProtoRawValue{}
				}
				field_values[field_num] << ProtoRawValue{
					bytes: data[pos..end]
					wire_type: wire_length_delimited
				}
				pos = end
			}
			wire_32bit {
				if pos + 4 > data.len {
					return error('truncated 32-bit field')
				}
				mut val := u32(0)
				for i in 0 .. 4 {
					val |= u32(data[pos + i]) << (u32(i) * 8)
				}
				pos += 4
				if field_num !in field_values {
					field_values[field_num] = []ProtoRawValue{}
				}
				field_values[field_num] << ProtoRawValue{
					fixed32: val
					wire_type: wire_32bit
				}
			}
			else {
				return error('unknown wire type: ${wire_type}')
			}
		}
	}

	// Now convert raw values to VrlValues using the descriptor
	mut result := new_object_map()

	for field_desc in msg_desc.fields {
		raw_vals := field_values[field_desc.number] or { continue }
		if raw_vals.len == 0 {
			continue
		}

		is_repeated := field_desc.label == 3

		if is_repeated {
			mut arr := []VrlValue{}
			for raw in raw_vals {
				// Handle packed repeated fields
				if raw.wire_type == wire_length_delimited
					&& proto_is_packable_type(field_desc.field_type) {
					packed := proto_decode_packed(raw.bytes, field_desc.field_type)!
					arr << packed
				} else {
					val := proto_raw_to_vrl(raw, field_desc, descs)!
					arr << val
				}
			}
			result.set(field_desc.name, VrlValue(arr))
		} else {
			// Use the last value (proto3 semantics)
			val := proto_raw_to_vrl(raw_vals[raw_vals.len - 1], field_desc, descs)!
			result.set(field_desc.name, val)
		}
	}

	return VrlValue(result)
}

struct ProtoRawValue {
	varint    u64
	fixed64   u64
	fixed32   u32
	bytes     []u8
	wire_type int
}

fn proto_is_packable_type(field_type int) bool {
	return field_type in [proto_type_double, proto_type_float, proto_type_int64,
		proto_type_uint64, proto_type_int32, proto_type_fixed64, proto_type_fixed32,
		proto_type_bool, proto_type_uint32, proto_type_enum, proto_type_sfixed32,
		proto_type_sfixed64, proto_type_sint32, proto_type_sint64]
}

fn proto_decode_packed(data []u8, field_type int) ![]VrlValue {
	mut result := []VrlValue{}
	mut pos := 0

	match field_type {
		proto_type_double {
			for pos + 8 <= data.len {
				bits := u64(data[pos]) | (u64(data[pos + 1]) << 8) | (u64(data[pos + 2]) << 16) | (u64(data[pos + 3]) << 24) | (u64(data[pos + 4]) << 32) | (u64(data[pos + 5]) << 40) | (u64(data[pos + 6]) << 48) | (u64(data[pos + 7]) << 56)
				unsafe {
					f := *(&f64(&bits))
					result << VrlValue(f)
				}
				pos += 8
			}
		}
		proto_type_float {
			for pos + 4 <= data.len {
				bits := u32(data[pos]) | (u32(data[pos + 1]) << 8) | (u32(data[pos + 2]) << 16) | (u32(data[pos + 3]) << 24)
				unsafe {
					f := *(&f32(&bits))
					result << VrlValue(f64(f))
				}
				pos += 4
			}
		}
		proto_type_fixed64, proto_type_sfixed64 {
			for pos + 8 <= data.len {
				mut val := u64(0)
				for i in 0 .. 8 {
					val |= u64(data[pos + i]) << (u32(i) * 8)
				}
				if field_type == proto_type_sfixed64 {
					result << VrlValue(i64(val))
				} else {
					result << VrlValue(i64(val))
				}
				pos += 8
			}
		}
		proto_type_fixed32, proto_type_sfixed32 {
			for pos + 4 <= data.len {
				mut val := u32(0)
				for i in 0 .. 4 {
					val |= u32(data[pos + i]) << (u32(i) * 8)
				}
				if field_type == proto_type_sfixed32 {
					result << VrlValue(i64(i32(val)))
				} else {
					result << VrlValue(i64(val))
				}
				pos += 4
			}
		}
		else {
			// Varint types
			for pos < data.len {
				val, new_pos := proto_decode_varint(data, pos)!
				pos = new_pos
				match field_type {
					proto_type_bool {
						result << VrlValue(val != 0)
					}
					proto_type_sint32 {
						result << VrlValue(i64(proto_zigzag_decode_32(u32(val))))
					}
					proto_type_sint64 {
						result << VrlValue(proto_zigzag_decode_64(val))
					}
					proto_type_enum {
						result << VrlValue(i64(val))
					}
					else {
						result << VrlValue(i64(val))
					}
				}
			}
		}
	}
	return result
}

fn proto_raw_to_vrl(raw ProtoRawValue, field_desc ProtoFieldDescriptor, descs ProtoFileDescriptors) !VrlValue {
	match field_desc.field_type {
		proto_type_double {
			if raw.wire_type == wire_64bit {
				bits := raw.fixed64
				unsafe {
					f := *(&f64(&bits))
					return VrlValue(f)
				}
			}
			return error('expected 64-bit wire type for double')
		}
		proto_type_float {
			if raw.wire_type == wire_32bit {
				bits := raw.fixed32
				unsafe {
					f := *(&f32(&bits))
					return VrlValue(f64(f))
				}
			}
			return error('expected 32-bit wire type for float')
		}
		proto_type_int64, proto_type_uint64 {
			return VrlValue(i64(raw.varint))
		}
		proto_type_int32, proto_type_uint32 {
			return VrlValue(i64(raw.varint))
		}
		proto_type_fixed64 {
			return VrlValue(i64(raw.fixed64))
		}
		proto_type_fixed32 {
			return VrlValue(i64(raw.fixed32))
		}
		proto_type_sfixed64 {
			return VrlValue(i64(raw.fixed64))
		}
		proto_type_sfixed32 {
			return VrlValue(i64(i32(raw.fixed32)))
		}
		proto_type_sint32 {
			return VrlValue(i64(proto_zigzag_decode_32(u32(raw.varint))))
		}
		proto_type_sint64 {
			return VrlValue(proto_zigzag_decode_64(raw.varint))
		}
		proto_type_bool {
			return VrlValue(raw.varint != 0)
		}
		proto_type_string {
			return VrlValue(raw.bytes.bytestr())
		}
		proto_type_bytes {
			return VrlValue(raw.bytes.bytestr())
		}
		proto_type_message {
			// Resolve the message type
			type_name := field_desc.type_name
			sub_desc := proto_find_message(descs, type_name) or {
				return error("unknown message type: '${type_name}'")
			}
			return proto_decode_message(raw.bytes, sub_desc, descs)
		}
		proto_type_enum {
			type_name := field_desc.type_name
			if enum_desc := proto_find_enum(descs, type_name) {
				num := int(raw.varint)
				for ev in enum_desc.values {
					if ev.number == num {
						return VrlValue(ev.name)
					}
				}
				// Fall back to integer
				return VrlValue(i64(num))
			}
			return VrlValue(i64(raw.varint))
		}
		else {
			return error('unsupported protobuf field type: ${field_desc.field_type}')
		}
	}
}

// --- Protobuf message encoding ---

fn proto_encode_message(obj ObjectMap, msg_desc ProtoMessageDescriptor, descs ProtoFileDescriptors) ![]u8 {
	mut result := []u8{}

	for field_desc in msg_desc.fields {
		val := obj.get(field_desc.name) or {
			// Try json_name
			if field_desc.json_name.len > 0 {
				obj.get(field_desc.json_name) or { continue }
			} else {
				continue
			}
		}

		// Skip null values
		match val {
			VrlNull { continue }
			else {}
		}

		is_repeated := field_desc.label == 3

		if is_repeated {
			arr := match val {
				[]VrlValue { val }
				else { continue }
			}
			for item in arr {
				encoded_field := proto_encode_field(field_desc, item, descs)!
				result << encoded_field
			}
		} else {
			encoded_field := proto_encode_field(field_desc, val, descs)!
			result << encoded_field
		}
	}

	return result
}

fn proto_encode_field(field_desc ProtoFieldDescriptor, val VrlValue, descs ProtoFileDescriptors) ![]u8 {
	mut result := []u8{}
	field_num := field_desc.number

	match field_desc.field_type {
		proto_type_double {
			tag := proto_encode_varint(u64((field_num << 3) | wire_64bit))
			result << tag
			f := match val {
				f64 { val }
				i64 { f64(val) }
				else { return error('expected float for double field') }
			}
			bits := unsafe { *(&u64(&f)) }
			for i in 0 .. 8 {
				result << u8(bits >> (u32(i) * 8))
			}
		}
		proto_type_float {
			tag := proto_encode_varint(u64((field_num << 3) | wire_32bit))
			result << tag
			f := match val {
				f64 { f32(val) }
				i64 { f32(val) }
				else { return error('expected float for float field') }
			}
			bits := unsafe { *(&u32(&f)) }
			for i in 0 .. 4 {
				result << u8(bits >> (u32(i) * 8))
			}
		}
		proto_type_int64, proto_type_uint64, proto_type_int32, proto_type_uint32 {
			tag := proto_encode_varint(u64((field_num << 3) | wire_varint))
			result << tag
			v := match val {
				i64 { u64(val) }
				f64 { u64(val) }
				string { u64(val.i64()) }
				else { return error('expected integer for int field') }
			}
			result << proto_encode_varint(v)
		}
		proto_type_sint32 {
			tag := proto_encode_varint(u64((field_num << 3) | wire_varint))
			result << tag
			v := match val {
				i64 { i32(val) }
				else { return error('expected integer for sint32 field') }
			}
			result << proto_encode_varint(u64(proto_zigzag_encode_32(v)))
		}
		proto_type_sint64 {
			tag := proto_encode_varint(u64((field_num << 3) | wire_varint))
			result << tag
			v := match val {
				i64 { val }
				else { return error('expected integer for sint64 field') }
			}
			result << proto_encode_varint(proto_zigzag_encode_64(v))
		}
		proto_type_fixed64, proto_type_sfixed64 {
			tag := proto_encode_varint(u64((field_num << 3) | wire_64bit))
			result << tag
			v := match val {
				i64 { u64(val) }
				else { return error('expected integer for fixed64 field') }
			}
			for i in 0 .. 8 {
				result << u8(v >> (u32(i) * 8))
			}
		}
		proto_type_fixed32, proto_type_sfixed32 {
			tag := proto_encode_varint(u64((field_num << 3) | wire_32bit))
			result << tag
			v := match val {
				i64 { u32(val) }
				else { return error('expected integer for fixed32 field') }
			}
			for i in 0 .. 4 {
				result << u8(v >> (u32(i) * 8))
			}
		}
		proto_type_bool {
			tag := proto_encode_varint(u64((field_num << 3) | wire_varint))
			result << tag
			v := match val {
				bool { if val { u64(1) } else { u64(0) } }
				else { return error('expected bool for bool field') }
			}
			result << proto_encode_varint(v)
		}
		proto_type_string {
			tag := proto_encode_varint(u64((field_num << 3) | wire_length_delimited))
			result << tag
			s := match val {
				string { val }
				i64 { '${val}' }
				f64 { '${val}' }
				bool { if val { 'true' } else { 'false' } }
				else { return error('expected string for string field') }
			}
			bytes := s.bytes()
			result << proto_encode_varint(u64(bytes.len))
			result << bytes
		}
		proto_type_bytes {
			tag := proto_encode_varint(u64((field_num << 3) | wire_length_delimited))
			result << tag
			s := match val {
				string { val }
				else { return error('expected bytes for bytes field') }
			}
			bytes := s.bytes()
			result << proto_encode_varint(u64(bytes.len))
			result << bytes
		}
		proto_type_message {
			type_name := field_desc.type_name
			sub_desc := proto_find_message(descs, type_name) or {
				return error("unknown message type: '${type_name}'")
			}
			sub_obj := match val {
				ObjectMap { val }
				else { return error('expected object for message field') }
			}
			sub_bytes := proto_encode_message(sub_obj, sub_desc, descs)!
			tag := proto_encode_varint(u64((field_num << 3) | wire_length_delimited))
			result << tag
			result << proto_encode_varint(u64(sub_bytes.len))
			result << sub_bytes
		}
		proto_type_enum {
			tag := proto_encode_varint(u64((field_num << 3) | wire_varint))
			result << tag
			v := match val {
				i64 { u64(val) }
				string {
					// Look up enum value by name
					type_name := field_desc.type_name
					if enum_desc := proto_find_enum(descs, type_name) {
						mut found := false
						mut enum_num := u64(0)
						for ev in enum_desc.values {
							if ev.name == val {
								enum_num = u64(ev.number)
								found = true
								break
							}
						}
						if !found {
							return error("unknown enum value: '${val}'")
						}
						enum_num
					} else {
						return error("unknown enum type: '${type_name}'")
					}
				}
				else { return error('expected integer or string for enum field') }
			}
			result << proto_encode_varint(v)
		}
		else {
			return error('unsupported protobuf field type for encoding: ${field_desc.field_type}')
		}
	}

	return result
}
