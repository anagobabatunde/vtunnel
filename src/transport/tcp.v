module transport

import net
import time

#include <netinet/tcp.h>

// TcpTransport wraps a net.TcpConn and implements the Transport interface.
@[heap]
pub struct TcpTransport {
pub mut:
	conn net.TcpConn
}

// new_tcp creates a TcpTransport from an existing TcpConn.
pub fn new_tcp(conn net.TcpConn) &TcpTransport {
	return &TcpTransport{
		conn: conn
	}
}

// set_nodelay disables Nagle's algorithm on a TCP connection for lower latency.
// Nagle buffers small writes for up to 40ms which destroys tunnel performance.
// Uses C interop because V's SocketOption enum does not include tcp_nodelay.
pub fn set_nodelay(mut conn net.TcpConn) {
	one := int(1)
	C.setsockopt(conn.sock.handle, C.IPPROTO_TCP, C.TCP_NODELAY, &one, sizeof(int))
}

// tune_socket increases kernel socket buffers and enables TCP keepalive.
// Larger buffers (256 KB) help when multiplexing many streams over one connection.
pub fn tune_socket(mut conn net.TcpConn) {
	conn.sock.set_option_int(.send_buf_size, 262144) or {}
	conn.sock.set_option_int(.receive_buf_size, 262144) or {}
	conn.sock.set_option_bool(.keep_alive, true) or {}
}

// set_read_timeout configures the read timeout on the underlying TCP connection.
pub fn (mut t TcpTransport) set_read_timeout(d time.Duration) {
	t.conn.read_timeout = d
}

// read implements Transport.
pub fn (mut t TcpTransport) read(mut buf []u8) !int {
	return t.conn.read(mut buf)
}

// write implements Transport.
pub fn (mut t TcpTransport) write(data []u8) !int {
	return t.conn.write(data)
}

// close implements Transport.
pub fn (mut t TcpTransport) close() ! {
	t.conn.close()!
}
