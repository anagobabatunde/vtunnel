module tunnel

// Stream represents one proxied connection multiplexed over a Tunnel.
@[heap]
pub struct Stream {
pub:
	id u32
pub mut:
	rx chan []u8
}

// new_stream allocates a Stream with a buffered receive channel.
pub fn new_stream(id u32) &Stream {
	return &Stream{
		id: id
		rx: chan []u8{cap: 64}
	}
}

// close closes the receive channel, signaling consumers to stop.
pub fn (mut s Stream) close() {
	s.rx.close()
}
