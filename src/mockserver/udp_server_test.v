module mockserver

import net

fn test_udp_server_start_and_address() {
	mut mock := start_udp()!
	defer { mock.stop() }

	assert mock.port > 0
	assert mock.address().starts_with('127.0.0.1:')
}

fn test_udp_server_captures_datagram() {
	mut mock := start_udp()!
	defer { mock.stop() }

	mut conn := net.dial_udp(mock.address()) or { return }
	defer { conn.close() or {} }

	conn.write('hello udp'.bytes()) or { return }

	msgs := mock.wait_for_datagrams(1, 3000)
	assert msgs.len >= 1
	assert msgs[0].data == 'hello udp'
}

fn test_udp_server_multiple_datagrams() {
	mut mock := start_udp()!
	defer { mock.stop() }

	for i in 0 .. 3 {
		mut conn := net.dial_udp(mock.address()) or { continue }
		conn.write('packet ${i}'.bytes()) or {}
		conn.close() or {}
	}

	msgs := mock.wait_for_datagrams(3, 3000)
	assert msgs.len >= 3

	mut found := [false, false, false]
	for m in msgs {
		if m.data == 'packet 0' { found[0] = true }
		if m.data == 'packet 1' { found[1] = true }
		if m.data == 'packet 2' { found[2] = true }
	}
	assert found[0]
	assert found[1]
	assert found[2]
}

fn test_udp_server_datagram_count() {
	mut mock := start_udp()!
	defer { mock.stop() }

	mut conn := net.dial_udp(mock.address()) or { return }
	conn.write('data'.bytes()) or {}
	conn.close() or {}

	mock.wait_for_datagrams(1, 3000)
	assert mock.datagram_count() >= 1
}
