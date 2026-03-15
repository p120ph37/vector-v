module sinks

import event
import net
import time

fn start_tcp_server(received chan string) int {
	ready := chan int{cap: 1}
	spawn fn (ready chan int, received chan string) {
		mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or {
			ready <- -1
			return
		}
		addr_str := (listener.addr() or { net.Addr{} }).str()
		colon := addr_str.last_index(':') or {
			ready <- -1
			return
		}
		port := addr_str[colon + 1..].int()
		ready <- port

		mut conn := listener.accept() or {
			received <- ''
			return
		}
		conn.set_read_timeout(3 * time.second)
		mut all_data := ''
		for {
			mut buf := []u8{len: 8192}
			n := conn.read(mut buf) or { break }
			if n == 0 {
				break
			}
			all_data += buf[..n].bytestr()
		}
		conn.close() or {}
		listener.close() or {}
		received <- all_data
	}(ready, received)

	mut port := -1
	for {
		if ready.try_pop(mut port) == .success {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	return port
}

fn test_socket_sink_tcp_send() {
	received := chan string{cap: 1}
	port := start_tcp_server(received)
	if port < 0 {
		return
	}

	mut s := new_socket_sink({
		'address':        '127.0.0.1:${port}'
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('tcp test message'))
	s.send(ev)!
	assert s.connected == true
	s.close()
	assert s.connected == false

	mut data := ''
	for _ in 0 .. 50 {
		if received.try_pop(mut data) == .success {
			break
		}
		time.sleep(100 * time.millisecond)
	}
	assert data.contains('tcp test message')
}

fn test_socket_sink_tcp_json() {
	received := chan string{cap: 1}
	port := start_tcp_server(received)
	if port < 0 {
		return
	}

	mut s := new_socket_sink({
		'address': '127.0.0.1:${port}'
	})!

	ev := event.Event(event.new_log('json tcp'))
	s.send(ev)!
	s.close()

	mut data := ''
	for _ in 0 .. 50 {
		if received.try_pop(mut data) == .success {
			break
		}
		time.sleep(100 * time.millisecond)
	}
	assert data.contains('"message"')
	assert data.contains('json tcp')
}

fn test_socket_sink_metric_tcp() {
	received := chan string{cap: 1}
	port := start_tcp_server(received)
	if port < 0 {
		return
	}

	mut s := new_socket_sink({
		'address': '127.0.0.1:${port}'
	})!

	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 42.0 })
	})
	s.send(metric)!
	s.close()

	mut data := ''
	for _ in 0 .. 50 {
		if received.try_pop(mut data) == .success {
			break
		}
		time.sleep(100 * time.millisecond)
	}
	assert data.contains('test.counter')
}

fn test_socket_sink_tcp_close_reclose() {
	received := chan string{cap: 1}
	port := start_tcp_server(received)
	if port < 0 {
		return
	}

	mut s := new_socket_sink({
		'address':        '127.0.0.1:${port}'
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('msg'))
	s.send(ev)!
	assert s.connected == true

	s.close()
	assert s.connected == false
	assert s.tcp_fd == -1

	// Double close should be safe
	s.close()
	assert s.connected == false
}

fn test_socket_sink_tcp_multiple_events() {
	received := chan string{cap: 1}
	port := start_tcp_server(received)
	if port < 0 {
		return
	}

	mut s := new_socket_sink({
		'address':        '127.0.0.1:${port}'
		'encoding.codec': 'text'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('line ${i}'))
		s.send(ev)!
	}
	s.close()

	mut data := ''
	for _ in 0 .. 50 {
		if received.try_pop(mut data) == .success {
			break
		}
		time.sleep(100 * time.millisecond)
	}
	assert data.contains('line 0')
	assert data.contains('line 4')
}
