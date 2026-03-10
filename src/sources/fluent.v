module sources

import event
import net
import time

// FluentSource implements the Fluent Forward Protocol v1 over TCP.
// Listens on a TCP port and decodes MessagePack-encoded fluent messages.
// Mirrors Vector's fluent source (src/sources/fluent/).
//
// Supported message modes:
//   - Message:       [tag, timestamp, record]
//   - Forward:       [tag, [[timestamp, record], ...]]
//   - PackedForward: [tag, packed_entries] (binary msgpack stream)
//   - Heartbeat:     nil
//
// DIVERGENCE FROM UPSTREAM: We implement a simplified msgpack decoder
// directly rather than depending on rmp_serde. Only the subset of
// msgpack needed for fluent protocol is supported.
pub struct FluentSource {
	address string = '0.0.0.0:24224'
}

// new_fluent creates a new FluentSource from config options.
pub fn new_fluent(opts map[string]string) FluentSource {
	mut address := '0.0.0.0:24224'
	if a := opts['address'] {
		address = a
	}
	return FluentSource{
		address: address
	}
}

// run listens for TCP connections and decodes fluent messages.
pub fn (s &FluentSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('fluent: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('fluent: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		spawn handle_fluent_conn(mut conn, output)
	}
}

fn handle_fluent_conn(mut conn net.TcpConn, output chan event.Event) {
	defer {
		conn.close() or {}
	}
	conn.set_read_timeout(30 * time.second)

	// Read data in a loop
	mut buf := []u8{len: 0, cap: 65536}
	for {
		mut tmp := []u8{len: 8192}
		bytes_read := conn.read(mut tmp) or { break }
		if bytes_read == 0 {
			break
		}
		buf << tmp[..bytes_read]

		// Try to decode messages from buffer
		for buf.len > 0 {
			result := decode_fluent_message(buf) or { break }
			// Emit events
			for ev in result.events {
				output <- ev
			}
			// Send ack if chunk present
			if result.chunk.len > 0 {
				ack_response := encode_msgpack_ack(result.chunk)
				conn.write(ack_response) or {}
			}
			// Advance buffer
			if result.consumed >= buf.len {
				buf.clear()
			} else {
				buf = buf[result.consumed..].clone()
			}
		}
	}
}

struct FluentDecodeResult {
	events   []event.Event
	consumed int
	chunk    string
}

// decode_fluent_message decodes a single fluent protocol message from msgpack bytes.
fn decode_fluent_message(data []u8) !FluentDecodeResult {
	if data.len == 0 {
		return error('empty data')
	}

	// Check for heartbeat (nil)
	if data[0] == 0xc0 {
		return FluentDecodeResult{
			consumed: 1
		}
	}

	// Fluent messages are msgpack arrays
	mut r := MsgpackReader{
		data: data
	}

	arr_len := r.read_array_len()!
	if arr_len < 2 {
		return error('invalid fluent message: array too short')
	}

	// First element: tag (string)
	tag := r.read_string()!

	if arr_len == 3 {
		// Could be Message [tag, timestamp, record] or PackedForward [tag, entries, options]
		// Peek at next byte to determine
		if r.pos >= data.len {
			return error('incomplete message')
		}
		next_byte := data[r.pos]

		if is_msgpack_int_or_ext(next_byte) {
			// Message mode: [tag, timestamp, record]
			ts := r.read_timestamp()!
			record := r.read_map()!

			mut ev := record_to_event(tag, ts, record)
			return FluentDecodeResult{
				events: [event.Event(ev)]
				consumed: r.pos
			}
		} else if is_msgpack_bin_or_str(next_byte) {
			// PackedForward: [tag, packed_bin]
			packed := r.read_bytes()!
			events := decode_packed_entries(tag, packed)
			return FluentDecodeResult{
				events: events
				consumed: r.pos
			}
		}
	}

	if arr_len == 2 {
		// Forward mode: [tag, [[ts, record], ...]]
		entries_len := r.read_array_len()!
		mut events := []event.Event{cap: entries_len}
		for _ in 0 .. entries_len {
			entry_len := r.read_array_len()!
			if entry_len < 2 {
				return error('invalid forward entry')
			}
			ts := r.read_timestamp()!
			record := r.read_map()!
			mut ev := record_to_event(tag, ts, record)
			events << event.Event(ev)
		}
		return FluentDecodeResult{
			events: events
			consumed: r.pos
		}
	}

	if arr_len == 4 {
		// MessageWithOptions: [tag, timestamp, record, options]
		// or PackedForwardWithOptions: [tag, packed, options_unused, options]
		next_byte := data[r.pos]
		if is_msgpack_int_or_ext(next_byte) {
			ts := r.read_timestamp()!
			record := r.read_map()!
			options := r.read_map()!
			chunk := get_chunk_from_options(options)

			mut ev := record_to_event(tag, ts, record)
			return FluentDecodeResult{
				events: [event.Event(ev)]
				consumed: r.pos
				chunk: chunk
			}
		}
	}

	return error('unsupported fluent message format')
}

fn record_to_event(tag string, ts i64, record map[string]string) event.LogEvent {
	mut fields := map[string]event.Value{}
	for k, v in record {
		fields[k] = event.Value(v)
	}
	fields['tag'] = event.Value(tag)
	if ts > 0 {
		fields['timestamp'] = event.Value(time.unix(ts))
	}

	return event.LogEvent{
		fields: fields
		meta: event.EventMetadata{
			source_type: 'fluent'
			ingest_timestamp: time.now()
		}
	}
}

fn decode_packed_entries(tag string, data []u8) []event.Event {
	mut events := []event.Event{}
	mut r := MsgpackReader{
		data: data
	}
	for r.pos < data.len {
		arr_len := r.read_array_len() or { break }
		if arr_len < 2 {
			break
		}
		ts := r.read_timestamp() or { break }
		record := r.read_map() or { break }
		mut ev := record_to_event(tag, ts, record)
		events << event.Event(ev)
	}
	return events
}

fn get_chunk_from_options(options map[string]string) string {
	return options['chunk'] or { '' }
}

fn encode_msgpack_ack(chunk string) []u8 {
	// Encode {"ack": chunk} in msgpack
	mut buf := []u8{}
	buf << 0x81 // fixmap with 1 entry
	// key "ack"
	buf << 0xa3 // fixstr len 3
	buf << `a`
	buf << `c`
	buf << `k`
	// value: chunk string
	if chunk.len < 32 {
		buf << u8(0xa0 | chunk.len)
	} else if chunk.len < 256 {
		buf << 0xd9
		buf << u8(chunk.len)
	} else {
		buf << 0xda
		buf << u8(chunk.len >> 8)
		buf << u8(chunk.len & 0xff)
	}
	buf << chunk.bytes()
	return buf
}

// MsgpackReader is a minimal msgpack decoder for the fluent protocol.
struct MsgpackReader {
	data []u8
mut:
	pos int
}

fn (mut r MsgpackReader) read_byte() !u8 {
	if r.pos >= r.data.len {
		return error('unexpected end of msgpack data')
	}
	b := r.data[r.pos]
	r.pos++
	return b
}

fn (mut r MsgpackReader) read_u16() !u16 {
	if r.pos + 2 > r.data.len {
		return error('unexpected end of msgpack data')
	}
	val := u16(r.data[r.pos]) << 8 | u16(r.data[r.pos + 1])
	r.pos += 2
	return val
}

fn (mut r MsgpackReader) read_u32() !u32 {
	if r.pos + 4 > r.data.len {
		return error('unexpected end of msgpack data')
	}
	val := u32(r.data[r.pos]) << 24 | u32(r.data[r.pos + 1]) << 16 | u32(r.data[r.pos + 2]) << 8 | u32(r.data[r.pos + 3])
	r.pos += 4
	return val
}

fn (mut r MsgpackReader) read_array_len() !int {
	b := r.read_byte()!
	if b >= 0x90 && b <= 0x9f {
		return int(b & 0x0f)
	}
	if b == 0xdc {
		return int(r.read_u16()!)
	}
	if b == 0xdd {
		return int(r.read_u32()!)
	}
	return error('expected msgpack array, got 0x${b:02x}')
}

fn (mut r MsgpackReader) read_string() !string {
	b := r.read_byte()!
	mut slen := 0
	if b >= 0xa0 && b <= 0xbf {
		slen = int(b & 0x1f)
	} else if b == 0xd9 {
		slen = int(r.read_byte()!)
	} else if b == 0xda {
		slen = int(r.read_u16()!)
	} else if b == 0xdb {
		slen = int(r.read_u32()!)
	} else {
		return error('expected msgpack string, got 0x${b:02x}')
	}
	if r.pos + slen > r.data.len {
		return error('string extends past end of data')
	}
	s := r.data[r.pos..r.pos + slen].bytestr()
	r.pos += slen
	return s
}

fn (mut r MsgpackReader) read_bytes() ![]u8 {
	b := r.read_byte()!
	mut blen := 0
	if b >= 0xa0 && b <= 0xbf {
		// fixstr used as bin
		blen = int(b & 0x1f)
	} else if b == 0xc4 {
		blen = int(r.read_byte()!)
	} else if b == 0xc5 {
		blen = int(r.read_u16()!)
	} else if b == 0xc6 {
		blen = int(r.read_u32()!)
	} else if b == 0xd9 {
		blen = int(r.read_byte()!)
	} else if b == 0xda {
		blen = int(r.read_u16()!)
	} else if b == 0xdb {
		blen = int(r.read_u32()!)
	} else {
		return error('expected msgpack bin/str, got 0x${b:02x}')
	}
	if r.pos + blen > r.data.len {
		return error('bytes extend past end of data')
	}
	result := r.data[r.pos..r.pos + blen].clone()
	r.pos += blen
	return result
}

fn (mut r MsgpackReader) read_timestamp() !i64 {
	b := r.data[r.pos]
	// Positive fixint
	if b <= 0x7f {
		r.pos++
		return i64(b)
	}
	// uint8
	if b == 0xcc {
		r.pos++
		return i64(r.read_byte()!)
	}
	// uint16
	if b == 0xcd {
		r.pos++
		return i64(r.read_u16()!)
	}
	// uint32
	if b == 0xce {
		r.pos++
		return i64(r.read_u32()!)
	}
	// uint64
	if b == 0xcf {
		r.pos++
		if r.pos + 8 > r.data.len {
			return error('unexpected end')
		}
		mut val := i64(0)
		for i in 0 .. 8 {
			val = (val << 8) | i64(r.data[r.pos + i])
		}
		r.pos += 8
		return val
	}
	// int32
	if b == 0xd2 {
		r.pos++
		v := r.read_u32()!
		return i64(i32(v))
	}
	// ext format (EventTime) - type 0
	if b == 0xd7 {
		// fixext 8: type + 8 bytes
		r.pos++
		ext_type := r.read_byte()!
		if ext_type == 0 {
			// EventTime: seconds (4 bytes) + nanoseconds (4 bytes)
			seconds := r.read_u32()!
			_ := r.read_u32()! // nanoseconds (ignored for now)
			return i64(seconds)
		}
		// Skip remaining 7 bytes for unknown ext
		r.pos += 7
		return i64(0)
	}
	// Negative fixint
	if b >= 0xe0 {
		r.pos++
		return i64(i8(b))
	}
	return error('expected msgpack integer/timestamp, got 0x${b:02x}')
}

fn (mut r MsgpackReader) read_map() !map[string]string {
	b := r.read_byte()!
	mut map_len := 0
	if b >= 0x80 && b <= 0x8f {
		map_len = int(b & 0x0f)
	} else if b == 0xde {
		map_len = int(r.read_u16()!)
	} else if b == 0xdf {
		map_len = int(r.read_u32()!)
	} else {
		return error('expected msgpack map, got 0x${b:02x}')
	}

	mut result := map[string]string{}
	for _ in 0 .. map_len {
		key := r.read_string()!
		val := r.read_value_as_string()!
		result[key] = val
	}
	return result
}

fn (mut r MsgpackReader) read_value_as_string() !string {
	if r.pos >= r.data.len {
		return error('unexpected end')
	}
	b := r.data[r.pos]

	// nil
	if b == 0xc0 {
		r.pos++
		return ''
	}
	// false
	if b == 0xc2 {
		r.pos++
		return 'false'
	}
	// true
	if b == 0xc3 {
		r.pos++
		return 'true'
	}
	// positive fixint
	if b <= 0x7f {
		r.pos++
		return '${b}'
	}
	// negative fixint
	if b >= 0xe0 {
		r.pos++
		return '${i8(b)}'
	}
	// uint8
	if b == 0xcc {
		r.pos++
		v := r.read_byte()!
		return '${v}'
	}
	// uint16
	if b == 0xcd {
		r.pos++
		v := r.read_u16()!
		return '${v}'
	}
	// uint32
	if b == 0xce {
		r.pos++
		v := r.read_u32()!
		return '${v}'
	}
	// int8
	if b == 0xd0 {
		r.pos++
		v := r.read_byte()!
		return '${i8(v)}'
	}
	// int16
	if b == 0xd1 {
		r.pos++
		v := r.read_u16()!
		return '${i16(v)}'
	}
	// int32
	if b == 0xd2 {
		r.pos++
		v := r.read_u32()!
		return '${i32(v)}'
	}
	// fixstr, str8, str16, str32
	if (b >= 0xa0 && b <= 0xbf) || b == 0xd9 || b == 0xda || b == 0xdb {
		return r.read_string()
	}
	// bin8, bin16, bin32
	if b == 0xc4 || b == 0xc5 || b == 0xc6 {
		data := r.read_bytes()!
		return data.bytestr()
	}
	// float32
	if b == 0xca {
		r.pos++
		bits := r.read_u32()!
		// Skip float conversion, return as hex
		return '${bits}'
	}
	// float64
	if b == 0xcb {
		r.pos++
		if r.pos + 8 > r.data.len {
			return error('unexpected end')
		}
		r.pos += 8
		return '0.0'
	}
	// For arrays, maps, ext types: skip and return placeholder
	r.skip_value()!
	return ''
}

fn (mut r MsgpackReader) skip_value() ! {
	if r.pos >= r.data.len {
		return error('unexpected end')
	}
	b := r.read_byte()!

	// nil, false, true
	if b == 0xc0 || b == 0xc2 || b == 0xc3 {
		return
	}
	// positive fixint, negative fixint
	if b <= 0x7f || b >= 0xe0 {
		return
	}
	// fixstr
	if b >= 0xa0 && b <= 0xbf {
		r.pos += int(b & 0x1f)
		return
	}
	// fixmap
	if b >= 0x80 && b <= 0x8f {
		count := int(b & 0x0f)
		for _ in 0 .. count * 2 {
			r.skip_value()!
		}
		return
	}
	// fixarray
	if b >= 0x90 && b <= 0x9f {
		count := int(b & 0x0f)
		for _ in 0 .. count {
			r.skip_value()!
		}
		return
	}
	// uint8, int8
	if b == 0xcc || b == 0xd0 {
		r.pos += 1
		return
	}
	// uint16, int16
	if b == 0xcd || b == 0xd1 {
		r.pos += 2
		return
	}
	// uint32, int32, float32
	if b == 0xce || b == 0xd2 || b == 0xca {
		r.pos += 4
		return
	}
	// uint64, int64, float64
	if b == 0xcf || b == 0xd3 || b == 0xcb {
		r.pos += 8
		return
	}
	// str8, bin8
	if b == 0xd9 || b == 0xc4 {
		slen := int(r.read_byte()!)
		r.pos += slen
		return
	}
	// str16, bin16
	if b == 0xda || b == 0xc5 {
		slen := int(r.read_u16()!)
		r.pos += slen
		return
	}
	// str32, bin32
	if b == 0xdb || b == 0xc6 {
		slen := int(r.read_u32()!)
		r.pos += slen
		return
	}
	// fixext 1,2,4,8,16
	if b == 0xd4 {
		r.pos += 2
		return
	}
	if b == 0xd5 {
		r.pos += 3
		return
	}
	if b == 0xd6 {
		r.pos += 5
		return
	}
	if b == 0xd7 {
		r.pos += 9
		return
	}
	if b == 0xd8 {
		r.pos += 17
		return
	}
	// array16
	if b == 0xdc {
		count := int(r.read_u16()!)
		for _ in 0 .. count {
			r.skip_value()!
		}
		return
	}
	// array32
	if b == 0xdd {
		count := int(r.read_u32()!)
		for _ in 0 .. count {
			r.skip_value()!
		}
		return
	}
	// map16
	if b == 0xde {
		count := int(r.read_u16()!)
		for _ in 0 .. count * 2 {
			r.skip_value()!
		}
		return
	}
	// map32
	if b == 0xdf {
		count := int(r.read_u32()!)
		for _ in 0 .. count * 2 {
			r.skip_value()!
		}
		return
	}
}

fn is_msgpack_int_or_ext(b u8) bool {
	// positive fixint, negative fixint, uint/int types, ext types
	return b <= 0x7f || b >= 0xe0 || (b >= 0xcc && b <= 0xd3) || (b >= 0xd4 && b <= 0xd8) || b == 0xce || b == 0xcf
}

fn is_msgpack_bin_or_str(b u8) bool {
	return (b >= 0xa0 && b <= 0xbf) || b == 0xc4 || b == 0xc5 || b == 0xc6 || b == 0xd9 || b == 0xda || b == 0xdb
}
