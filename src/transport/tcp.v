module transport

import net
import time

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
