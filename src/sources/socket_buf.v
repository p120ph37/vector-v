module sources


// SocketBuffer provides shared TCP/UDP socket listening and line-buffered
// reading infrastructure. Used by socket source, vector source, and websocket
// source. This parallels upstream Vector's approach where socket-based sources
// share a common framing/buffering layer.
//
// The buffer accumulates bytes from a TCP connection and emits complete
// lines (delimited by \n). This framing strategy is shared across:
//   - SocketSource (generic TCP/UDP line protocol)
//   - VectorSource (Vector's native JSON-over-TCP protocol)
//   - WebSocketSource (for TCP fallback / raw mode)
pub struct SocketBuffer {
	max_length int = 102400
mut:
	buf []u8
}

// new_socket_buffer creates a SocketBuffer with the given max line length.
pub fn new_socket_buffer(max_length int) SocketBuffer {
	ml := if max_length <= 0 { 102400 } else { max_length }
	return SocketBuffer{
		max_length: ml
	}
}

// feed appends raw bytes to the buffer. Call read_lines() after to extract
// complete lines.
pub fn (mut sb SocketBuffer) feed(data []u8) {
	sb.buf << data
}

// read_lines extracts all complete newline-delimited lines from the buffer,
// leaving any partial trailing data in the buffer for the next feed().
pub fn (mut sb SocketBuffer) read_lines() []string {
	mut lines := []string{}
	for {
		idx := find_newline(sb.buf)
		if idx < 0 {
			break
		}
		mut line := sb.buf[..idx].bytestr().trim_right('\r')
		if line.len > sb.max_length {
			line = line[..sb.max_length]
		}
		lines << line
		if idx + 1 >= sb.buf.len {
			sb.buf.clear()
		} else {
			sb.buf = sb.buf[idx + 1..].clone()
		}
	}
	// If buffer exceeds max_length without a newline, flush it as a line
	if sb.buf.len > sb.max_length {
		line := sb.buf[..sb.max_length].bytestr()
		lines << line
		sb.buf = sb.buf[sb.max_length..].clone()
	}
	return lines
}

// remaining returns any data left in the buffer.
pub fn (sb &SocketBuffer) remaining() string {
	return sb.buf.bytestr()
}

// clear empties the buffer.
pub fn (mut sb SocketBuffer) clear() {
	sb.buf.clear()
}

fn find_newline(data []u8) int {
	for i, b in data {
		if b == `\n` {
			return i
		}
	}
	return -1
}

