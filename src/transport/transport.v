module transport

// Transport is the abstraction over the raw byte connection (TCP, TLS, WebSocket, etc.).
pub interface Transport {
mut:
	// read reads up to buf.len bytes into buf. Returns number of bytes read.
	read(mut buf []u8) !int
	// write sends the given data. Returns number of bytes written.
	write(data []u8) !int
	// close shuts down the transport.
	close() !
}

// TransportReader adapts a Transport for use as an io.Reader.
// Needed because V cannot directly cast between interface types.
@[heap]
pub struct TransportReader {
mut:
	t Transport
}

// new_reader creates an io.Reader-compatible wrapper around a Transport.
pub fn new_reader(t Transport) &TransportReader {
	return &TransportReader{
		t: t
	}
}

// read implements io.Reader.
pub fn (mut r TransportReader) read(mut buf []u8) !int {
	return r.t.read(mut buf)
}
