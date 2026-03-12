module tunnel

import io
import net
import time
import src.slog
import src.protocol
import src.transport

// Keepalive interval for sending ping frames.
pub const ping_interval = 30 * time.second

// Idle timeout for detecting dead connections (2x ping interval).
pub const idle_timeout = 60 * time.second

// Maximum number of concurrent streams per tunnel to prevent resource exhaustion.
pub const max_streams = 1024

// Tunnel manages a multiplexed control connection.
@[heap]
pub struct Tunnel {
pub mut:
	transport  transport.Transport
	streams    shared map[u32]&Stream
	write_ch   chan []u8
	id_counter chan u32
	logger     &slog.Logger = unsafe { nil }
}

// new creates a Tunnel over the given Transport.
pub fn new(t transport.Transport) &Tunnel {
	id_ch := chan u32{cap: 1}
	// Seed the first ID
	id_ch <- u32(1)
	return &Tunnel{
		transport:  t
		write_ch:   chan []u8{cap: 512}
		id_counter: id_ch
	}
}

// stream_count returns the number of active streams.
pub fn (mut tun Tunnel) stream_count() int {
	mut count := 0
	rlock tun.streams {
		count = tun.streams.len
	}
	return count
}

// open_stream allocates a new Stream and registers it.
pub fn (mut tun Tunnel) open_stream(id u32) &Stream {
	s := new_stream(id)
	lock tun.streams {
		tun.streams[id] = s
	}
	return s
}

// next_stream_id returns the next stream ID and increments.
// Thread-safe: uses a channel as an atomic counter.
// Skips ID 0 on wraparound since 0 is reserved for control frames.
pub fn (mut tun Tunnel) next_stream_id() u32 {
	id := <-tun.id_counter or { return 0 }
	mut next := id + 1
	if next == 0 {
		next = 1 // skip 0 — reserved for control frames
	}
	tun.id_counter <- next
	return id
}

// get_stream retrieves a Stream by ID.
pub fn (mut tun Tunnel) get_stream(id u32) ?&Stream {
	rlock tun.streams {
		return tun.streams[id] or { return none }
	}
}

// remove_stream removes a stream from the map and closes its channel.
pub fn (mut tun Tunnel) remove_stream(id u32) {
	lock tun.streams {
		if s := tun.streams[id] {
			s.rx.close()
		}
		tun.streams.delete(id)
	}
}

// send encodes a frame and queues it for writing.
// Safe to call after tunnel is closed — silently drops the frame.
@[inline]
pub fn (mut tun Tunnel) send(f protocol.Frame) {
	data := f.encode()
	tun.write_ch.try_push(&data)
}

// run_write_loop drains write_ch and writes serialized frames to the transport.
// Exits when write_ch is closed or a write error occurs.
// On write error, closes the transport to unblock the read loop.
pub fn (mut tun Tunnel) run_write_loop() {
	for {
		data := <-tun.write_ch or { break }
		tun.transport.write(data) or {
			tun.transport.close() or {}
			break
		}
	}
}

// run_ping_loop sends ping frames at regular intervals to keep the connection alive.
// Exits when the write channel is closed (tunnel shutting down).
pub fn (mut tun Tunnel) run_ping_loop() {
	for {
		time.sleep(ping_interval)
		data := protocol.new_frame(0, .ping, []).encode()
		state := tun.write_ch.try_push(&data)
		if state == .closed {
			break
		}
	}
}

// run_read_loop reads frames from the transport and dispatches to streams.
// Calls on_open when a DataOpen frame arrives.
// Uses io.BufferedReader (128 KB) to batch syscalls — one kernel read serves many frames.
pub fn (mut tun Tunnel) run_read_loop(on_open fn (u32, []u8)) {
	mut rdr := transport.new_reader(tun.transport)
	mut br := io.new_buffered_reader(reader: rdr, cap: 131072)
	mut reader := io.Reader(br)
	for {
		f := protocol.read_frame(mut reader) or { break }
		match f.msg_type {
			.data_open {
				on_open(f.stream_id, f.payload)
			}
			.data {
				if s := tun.get_stream(f.stream_id) {
					state := s.rx.try_push(&f.payload)
					if state == .not_ready {
						if tun.logger != unsafe { nil } {
							tun.logger.warn('rx buffer full, closing stream',
								stream_id: int(f.stream_id)
							)
						}
						tun.send(protocol.new_frame(f.stream_id, .data_close, []))
						tun.remove_stream(f.stream_id)
					}
				}
			}
			.data_close {
				tun.remove_stream(f.stream_id)
			}
			.ping {
				tun.send(protocol.new_frame(0, .pong, []))
			}
			.pong {
				// Keepalive response received; socket read timeout resets automatically
			}
			else {}
		}
	}
}

// read_frame reads a single protocol frame from the transport.
// Used during handshake (auth, registration) before the read loop starts.
pub fn (mut tun Tunnel) read_frame() !protocol.Frame {
	mut rdr := transport.new_reader(tun.transport)
	mut br := io.new_buffered_reader(reader: rdr, cap: 131072)
	mut reader := io.Reader(br)
	return protocol.read_frame(mut reader)
}

// write_raw writes raw bytes directly to the transport.
// Used during handshake (auth, registration) before the write loop starts.
pub fn (mut tun Tunnel) write_raw(data []u8) ! {
	tun.transport.write(data)!
}

// close shuts down the tunnel.
pub fn (mut tun Tunnel) close() {
	tun.write_ch.close()
	tun.id_counter.close()
	tun.transport.close() or {}
}

// pipe_conn_to_stream reads from a TCP connection and sends Data frames.
// Used for local connections (visitor <-> local service), not the tunnel transport.
pub fn pipe_conn_to_stream(mut conn net.TcpConn, mut tun Tunnel, s &Stream) {
	mut buf := []u8{len: 65536}
	for {
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		tun.send(protocol.new_frame(s.id, .data, buf[..n].clone()))
	}
}

// pipe_stream_to_conn reads from stream.rx and writes to a TCP connection.
// Used for local connections (visitor <-> local service), not the tunnel transport.
pub fn pipe_stream_to_conn(mut conn net.TcpConn, s &Stream) {
	for {
		data := <-s.rx or { break }
		conn.write(data) or { break }
	}
}
