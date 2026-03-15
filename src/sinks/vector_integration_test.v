module sinks

import event
import net
import time

fn test_vector_sink_tcp_flush() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { return }
	addr := listener.addr() or {
		listener.close() or {}
		return
	}
	port := addr.port() or { return }

	received := chan string{cap: 1}
	spawn fn (mut listener net.TcpListener, received chan string) {
		mut conn := listener.accept() or {
			received <- ''
			return
		}
		conn.set_read_timeout(3 * time.second)
		mut buf := []u8{len: 16384}
		n := conn.read(mut buf) or {
			conn.close() or {}
			received <- ''
			return
		}
		data := buf[..n].bytestr()
		conn.close() or {}
		received <- data
	}(mut listener, received)
	defer { listener.close() or {} }

	time.sleep(50 * time.millisecond)

	mut s := new_vector({
		'address':          '127.0.0.1:${port}'
		'batch.max_events': '1000'
	})

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('vector msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 3

	s.flush()!
	assert s.total_buffered() == 0
	assert s.connected == true

	mut data := ''
	if received.try_pop(mut data) != .success {
		time.sleep(500 * time.millisecond)
		received.try_pop(mut data)
	}
	assert data.contains('vector msg 0')
	assert data.contains('vector msg 1')
	assert data.contains('vector msg 2')

	s.close()
	assert s.connected == false
}

fn test_vector_sink_auto_flush() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { return }
	addr := listener.addr() or {
		listener.close() or {}
		return
	}
	port := addr.port() or { return }

	// Accept in background
	spawn fn (mut listener net.TcpListener) {
		mut conn := listener.accept() or { return }
		conn.set_read_timeout(3 * time.second)
		mut buf := []u8{len: 8192}
		conn.read(mut buf) or {}
		conn.close() or {}
	}(mut listener)
	defer { listener.close() or {} }

	time.sleep(50 * time.millisecond)

	mut s := new_vector({
		'address':          '127.0.0.1:${port}'
		'batch.max_events': '2'
	})

	ev1 := event.Event(event.new_log('batch msg 1'))
	ev2 := event.Event(event.new_log('batch msg 2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	assert s.total_buffered() == 0

	s.close()
}
