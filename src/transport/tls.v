module transport

import net.mbedtls
import time

// TlsTransport wraps an mbedtls.SSLConn and implements the Transport interface.
@[heap]
pub struct TlsTransport {
pub mut:
	conn &mbedtls.SSLConn
}

// new_tls wraps an existing SSLConn as a TLS transport (server-side accepted connections).
pub fn new_tls(conn &mbedtls.SSLConn) &TlsTransport {
	return &TlsTransport{
		conn: conn
	}
}

// new_tls_client creates a client-side TLS transport by dialing the given host:port.
// If ca_path is non-empty, the server certificate is validated against it.
// If ca_path is empty, certificate verification is skipped (insecure, dev only).
pub fn new_tls_client(host string, port int, ca_path string) !&TlsTransport {
	mut conn := mbedtls.new_ssl_conn(mbedtls.SSLConnectConfig{
		verify:   ca_path
		validate: ca_path != ''
	})!
	conn.dial(host, port)!
	return &TlsTransport{
		conn: conn
	}
}

// set_read_timeout configures the read timeout on the underlying TLS connection.
pub fn (mut t TlsTransport) set_read_timeout(d time.Duration) {
	t.conn.duration = d
}

// read implements Transport.
pub fn (mut t TlsTransport) read(mut buf []u8) !int {
	return t.conn.read(mut buf)
}

// write implements Transport.
pub fn (mut t TlsTransport) write(data []u8) !int {
	return t.conn.write(data)
}

// close implements Transport.
pub fn (mut t TlsTransport) close() ! {
	t.conn.shutdown()!
}
