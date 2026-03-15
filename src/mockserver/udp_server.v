module mockserver

import net
import time

// MockUdpServer provides a UDP socket mock server for testing UDP-based
// components (SocketSink in UDP mode, SocketSource in UDP mode).
//
// Usage:
//   mut mock := mockserver.start_udp()!
//   defer { mock.stop() }
//
//   // Send UDP packets to mock.address()...
//
//   msgs := mock.wait_for_datagrams(2, 5000)
//   assert msgs.len == 2

// CapturedDatagram stores a UDP datagram received by the mock server.
pub struct CapturedDatagram {
pub:
	data string
	peer string
}

// MockUdpServer listens on 127.0.0.1 with a kernel-assigned port.
pub struct MockUdpServer {
pub:
	port int
mut:
	capture   chan CapturedDatagram
	collected []CapturedDatagram
}

// start_udp starts a UDP mock server on a random port.
pub fn start_udp() !MockUdpServer {
	ready := chan int{cap: 1}
	capture := chan CapturedDatagram{cap: 10000}

	spawn run_udp_server(capture, ready)

	port := <-ready
	if port < 0 {
		return error('mockserver: could not bind UDP to loopback port')
	}

	return MockUdpServer{
		port: port
		capture: capture
	}
}

// address returns the listen address (e.g. "127.0.0.1:34567").
pub fn (s &MockUdpServer) address() string {
	return '127.0.0.1:${s.port}'
}

// wait_for_datagrams blocks until at least `count` datagrams have been captured,
// or timeout_ms milliseconds have elapsed.
pub fn (mut s MockUdpServer) wait_for_datagrams(count int, timeout_ms int) []CapturedDatagram {
	deadline := time.now().unix_milli() + timeout_ms
	for s.collected.len < count {
		if time.now().unix_milli() >= deadline {
			break
		}
		mut msg := CapturedDatagram{}
		if s.capture.try_pop(mut msg) == .success {
			s.collected << msg
		} else {
			time.sleep(5 * time.millisecond)
		}
	}
	return s.collected
}

// datagrams non-blocking drains pending datagrams.
pub fn (mut s MockUdpServer) datagrams() []CapturedDatagram {
	for {
		mut msg := CapturedDatagram{}
		if s.capture.try_pop(mut msg) == .success {
			s.collected << msg
		} else {
			break
		}
	}
	return s.collected
}

// datagram_count returns the total number of datagrams captured.
pub fn (mut s MockUdpServer) datagram_count() int {
	_ = s.datagrams()
	return s.collected.len
}

// stop closes the capture channel.
pub fn (mut s MockUdpServer) stop() {
	s.capture.close()
}

// --- Internal UDP server ---

fn run_udp_server(capture chan CapturedDatagram, ready chan int) {
	mut conn := net.listen_udp('127.0.0.1:0') or {
		ready <- -1
		return
	}

	// UdpConn has no addr() method; use getsockname to discover the bound port.
	mut sa := C.sockaddr_in{}
	mut sa_len := u32(sizeof(C.sockaddr_in))
	if C.getsockname(conn.sock.handle, voidptr(&sa), &sa_len) != 0 {
		ready <- -1
		return
	}
	port := int(C.ntohs(sa.sin_port))
	if port == 0 {
		ready <- -1
		return
	}
	ready <- port

	for {
		mut buf := []u8{len: 65536}
		n, addr := conn.read(mut buf) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		if n == 0 {
			continue
		}
		capture.try_push(CapturedDatagram{
			data: buf[..n].bytestr()
			peer: addr.str()
		})
	}
}
