module tunnel

import net
import src.protocol
import src.transport

// --- new_stream ---

fn test_new_stream_id() {
	s := new_stream(42)
	assert s.id == 42
}

fn test_new_stream_channel_open() {
	s := new_stream(1)
	// Should be able to push and pop
	data := [u8(1), 2, 3]
	s.rx.try_push(&data)
	received := <-s.rx or { []u8{} }
	assert received == [u8(1), 2, 3]
}

fn test_stream_close() {
	mut s := new_stream(1)
	s.close()
	// After close, try_push should return .closed
	data := [u8(1)]
	state := s.rx.try_push(&data)
	assert state == .closed
}

fn test_stream_close_idempotent() {
	mut s := new_stream(1)
	s.close()
	// Second close should not panic (V channels handle double-close)
	s.close()
}

// --- Stream channel capacity ---

fn test_stream_channel_buffered() {
	s := new_stream(1)
	// Should be able to push multiple items without blocking
	for i in 0 .. 10 {
		data := [u8(i)]
		s.rx.try_push(&data)
	}
	// Read them back
	for i in 0 .. 10 {
		received := <-s.rx or { break }
		assert received[0] == u8(i)
	}
}

// --- Tunnel helpers ---

fn new_tunnel_for_test() &Tunnel {
	id_ch := chan u32{cap: 1}
	id_ch <- u32(1)
	// Use a TcpTransport wrapping a default TcpConn for testing
	t := transport.new_tcp(net.TcpConn{})
	return &Tunnel{
		transport:  t
		write_ch:   chan []u8{cap: 128}
		id_counter: id_ch
	}
}

// --- next_stream_id ---

fn test_next_stream_id_increments() {
	mut tun := new_tunnel_for_test()
	id1 := tun.next_stream_id()
	id2 := tun.next_stream_id()
	id3 := tun.next_stream_id()
	assert id1 == 1
	assert id2 == 2
	assert id3 == 3
}

// --- open_stream / remove_stream ---

fn test_open_stream_registers() {
	mut tun := new_tunnel_for_test()
	s := tun.open_stream(42)
	assert s.id == 42
	// Verify stream is in the map
	mut found := false
	rlock tun.streams {
		if _ := tun.streams[42] {
			found = true
		}
	}
	assert found, 'stream 42 should exist in map'
}

fn test_remove_stream_deletes_and_closes() {
	mut tun := new_tunnel_for_test()
	s := tun.open_stream(1)
	tun.remove_stream(1)
	// Stream should be gone
	mut count := 0
	rlock tun.streams {
		count = tun.streams.len
	}
	assert count == 0, 'stream map should be empty after remove'
	// Channel should be closed
	data := [u8(1)]
	state := s.rx.try_push(&data)
	assert state == .closed
}

// --- send ---

fn test_send_queues_encoded_frame() {
	mut tun := new_tunnel_for_test()
	f := protocol.new_frame(5, .data, [u8(0xAA)])
	tun.send(f)
	encoded := <-tun.write_ch or {
		assert false, 'write_ch should have data'
		return
	}
	assert encoded.len == protocol.header_size + 1
}

fn test_send_on_closed_channel_does_not_panic() {
	mut tun := new_tunnel_for_test()
	tun.write_ch.close()
	// Should not panic — try_push silently drops on closed channel
	tun.send(protocol.new_frame(0, .ping, []))
}

// --- keepalive constants ---

fn test_idle_timeout_greater_than_ping_interval() {
	assert idle_timeout > ping_interval, 'idle timeout must exceed ping interval'
}
