module sources

import event
import time

// DnstapSource listens on a Unix domain socket or TCP socket and receives
// dnstap-format DNS telemetry data. DNStap is a protocol for DNS servers
// to log DNS queries/responses using Frame Streams over Unix domain sockets
// or TCP. Mirrors Vector's dnstap source concept.
//
// Since V doesn't have protobuf support, we implement a simplified dnstap
// frame parser that extracts key fields from the binary frame format.
//
// Config options:
//   socket_path:      Unix socket path (required for unix mode)
//   host:             TCP listen host (default: 0.0.0.0)
//   port:             TCP listen port (default: 6000)
//   mode:             'tcp' or 'unix' (default: tcp)
//   max_frame_length: Maximum frame size in bytes (default: 102400)
//   content_type:     Frame Streams content type (default: protobuf:dnstap.Dnstap)
pub struct DnstapSource {
	socket_path      string
	host             string = '0.0.0.0'
	port             int    = 6000
	mode             string = 'tcp'
	max_frame_length int    = 102400
	content_type     string = 'protobuf:dnstap.Dnstap'
}

// FrameStreamControl represents a parsed Frame Streams control frame.
// Control types: 1=ACCEPT, 2=START, 3=STOP, 4=READY, 5=FINISH
pub struct FrameStreamControl {
pub:
	control_type int
	content_type string
}

// DnstapMessage represents a parsed dnstap protobuf message with key fields
// extracted from the wire format.
pub struct DnstapMessage {
pub:
	identity          string
	version           string
	message_type      int
	message_type_name string
	raw_data          []u8
}

// new_dnstap creates a new DnstapSource from config options.
// Returns error if mode is invalid or if unix mode is used without socket_path.
pub fn new_dnstap(opts map[string]string) !DnstapSource {
	socket_path := opts['socket_path'] or { '' }

	mut host := opts['host'] or { '0.0.0.0' }
	if host.len == 0 {
		host = '0.0.0.0'
	}

	mut port := 6000
	if p := opts['port'] {
		port = p.int()
		if port <= 0 {
			port = 6000
		}
	}

	mode := opts['mode'] or { 'tcp' }
	if mode != 'tcp' && mode != 'unix' {
		return error("dnstap: mode must be 'tcp' or 'unix', got '${mode}'")
	}
	if mode == 'unix' && socket_path.len == 0 {
		return error('dnstap: socket_path is required for unix mode')
	}

	mut max_frame_length := 102400
	if mfl := opts['max_frame_length'] {
		max_frame_length = mfl.int()
		if max_frame_length <= 0 {
			max_frame_length = 102400
		}
	}

	content_type := opts['content_type'] or { 'protobuf:dnstap.Dnstap' }

	return DnstapSource{
		socket_path: socket_path
		host: host
		port: port
		mode: mode
		max_frame_length: max_frame_length
		content_type: content_type
	}
}

// run starts the dnstap listener and emits log events for each dnstap message.
// Listens on the configured socket (TCP or Unix) and parses incoming Frame
// Streams data containing dnstap protobuf messages.
pub fn (s &DnstapSource) run(output chan event.Event) {
	// TODO: implement listening loop
	// 1. Bind to TCP (host:port) or Unix domain socket (socket_path)
	// 2. Accept connections
	// 3. For each connection, read Frame Streams framing:
	//    a. Read 4-byte big-endian length prefix
	//    b. If length == 0, read control frame (READY/START/STOP/FINISH)
	//    c. If length > 0, read data frame and parse as dnstap protobuf
	// 4. Convert parsed DnstapMessage to log event and send to output
	_ = s
	_ = output
	_ = time.now()
}

// parse_frame_stream_control parses a Frame Streams control frame from raw bytes.
// Frame Streams uses a 4-byte big-endian length prefix. If length == 0, the
// following data is a control frame:
//   4-byte zero (escape sequence)
//   4-byte control frame length
//   4-byte control type (1=ACCEPT, 2=START, 3=STOP, 4=READY, 5=FINISH)
//   Optional: 4-byte content type field type + 4-byte content type length + content type bytes
pub fn parse_frame_stream_control(data []u8) FrameStreamControl {
	if data.len < 12 {
		return FrameStreamControl{}
	}

	// First 4 bytes should be zero (escape sequence)
	escape := u32(data[0]) << 24 | u32(data[1]) << 16 | u32(data[2]) << 8 | u32(data[3])
	if escape != 0 {
		return FrameStreamControl{}
	}

	// Next 4 bytes: control frame length
	// control_len := u32(data[4]) << 24 | u32(data[5]) << 16 | u32(data[6]) << 8 | u32(data[7])

	// Next 4 bytes: control type
	control_type := int(u32(data[8]) << 24 | u32(data[9]) << 16 | u32(data[10]) << 8 | u32(data[11]))

	mut content_type := ''
	// Check for optional content type field (field type 1)
	if data.len >= 24 {
		field_type := u32(data[12]) << 24 | u32(data[13]) << 16 | u32(data[14]) << 8 | u32(data[15])
		if field_type == 1 {
			ct_len := int(u32(data[16]) << 24 | u32(data[17]) << 16 | u32(data[18]) << 8 | u32(data[19]))
			if data.len >= 20 + ct_len {
				content_type = data[20..20 + ct_len].bytestr()
			}
		}
	}

	return FrameStreamControl{
		control_type: control_type
		content_type: content_type
	}
}

// read_protobuf_varint reads a protobuf varint from data at the given offset.
// Returns (value, bytes_consumed). Standard protobuf varint encoding: each byte
// uses 7 data bits and 1 continuation bit (MSB).
pub fn read_protobuf_varint(data []u8, offset int) (u64, int) {
	mut result := u64(0)
	mut shift := u32(0)
	mut pos := offset

	for pos < data.len {
		b := data[pos]
		result |= u64(b & 0x7F) << shift
		pos++
		if b & 0x80 == 0 {
			return result, pos - offset
		}
		shift += 7
		if shift >= 64 {
			break
		}
	}

	return result, pos - offset
}

// read_protobuf_field reads a single protobuf field from data at the given offset.
// Returns (field_number, wire_type, field_data, new_offset).
// Wire types: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit
pub fn read_protobuf_field(data []u8, offset int) (int, int, []u8, int) {
	if offset >= data.len {
		return 0, 0, []u8{}, offset
	}

	// Read field tag (varint)
	tag, tag_len := read_protobuf_varint(data, offset)
	if tag_len == 0 {
		return 0, 0, []u8{}, offset
	}

	field_number := int(tag >> 3)
	wire_type := int(tag & 0x07)
	mut pos := offset + tag_len

	match wire_type {
		0 {
			// Varint
			val, val_len := read_protobuf_varint(data, pos)
			if val_len == 0 {
				return field_number, wire_type, []u8{}, pos
			}
			// Encode varint value as bytes for uniform return
			mut buf := []u8{}
			mut v := val
			for {
				buf << u8(v & 0xFF)
				v >>= 8
				if v == 0 {
					break
				}
			}
			return field_number, wire_type, buf, pos + val_len
		}
		1 {
			// 64-bit fixed
			if pos + 8 > data.len {
				return field_number, wire_type, []u8{}, pos
			}
			return field_number, wire_type, data[pos..pos + 8].clone(), pos + 8
		}
		2 {
			// Length-delimited
			length, len_bytes := read_protobuf_varint(data, pos)
			pos += len_bytes
			end := pos + int(length)
			if end > data.len {
				return field_number, wire_type, []u8{}, pos
			}
			return field_number, wire_type, data[pos..end].clone(), end
		}
		5 {
			// 32-bit fixed
			if pos + 4 > data.len {
				return field_number, wire_type, []u8{}, pos
			}
			return field_number, wire_type, data[pos..pos + 4].clone(), pos + 4
		}
		else {
			return field_number, wire_type, []u8{}, pos
		}
	}
}

// parse_dnstap_fields extracts protobuf fields from a dnstap message by scanning
// for known field tags in the wire format. Returns a map of field number (as string)
// to field value (as string). Varint fields are decoded as decimal strings;
// length-delimited fields are returned as their raw string content.
pub fn parse_dnstap_fields(data []u8) map[string]string {
	mut fields := map[string]string{}
	mut offset := 0

	for offset < data.len {
		field_number, wire_type, field_data, new_offset := read_protobuf_field(data, offset)
		if new_offset <= offset {
			break
		}
		offset = new_offset

		if field_data.len == 0 {
			continue
		}

		key := '${field_number}'
		match wire_type {
			0 {
				// Varint: reconstruct value from stored bytes
				mut val := u64(0)
				for i, b in field_data {
					val |= u64(b) << (u32(i) * 8)
				}
				fields[key] = '${val}'
			}
			2 {
				// Length-delimited: store as string
				fields[key] = field_data.bytestr()
			}
			else {
				fields[key] = field_data.bytestr()
			}
		}
	}

	return fields
}

// parse_dnstap_frame parses a dnstap protobuf message from raw bytes.
// Extracts key fields:
//   Field 1 (varint): identity
//   Field 2 (varint): version
//   Field 3 (length-delimited): extra
//   Field 14 (varint): message_type
//   Field 15 (length-delimited): response_message
pub fn parse_dnstap_frame(data []u8) DnstapMessage {
	fields := parse_dnstap_fields(data)

	identity := fields['1'] or { '' }
	version := fields['2'] or { '' }
	msg_type_str := fields['14'] or { '0' }
	msg_type := msg_type_str.int()

	return DnstapMessage{
		identity: identity
		version: version
		message_type: msg_type
		message_type_name: dnstap_message_type_name(msg_type)
		raw_data: data.clone()
	}
}

// dnstap_message_type_name returns the human-readable name for a dnstap message type.
pub fn dnstap_message_type_name(t int) string {
	return match t {
		1 { 'AUTH_QUERY' }
		2 { 'AUTH_RESPONSE' }
		3 { 'RESOLVER_QUERY' }
		4 { 'RESOLVER_RESPONSE' }
		5 { 'CLIENT_QUERY' }
		6 { 'CLIENT_RESPONSE' }
		7 { 'FORWARDER_QUERY' }
		8 { 'FORWARDER_RESPONSE' }
		9 { 'STUB_QUERY' }
		10 { 'STUB_RESPONSE' }
		11 { 'TOOL_QUERY' }
		12 { 'TOOL_RESPONSE' }
		else { 'UNKNOWN' }
	}
}
