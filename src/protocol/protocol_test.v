module protocol

import io

// --- new_frame ---

fn test_new_frame_constructs_correctly() {
	f := new_frame(42, .data, [u8(1), 2, 3])
	assert f.stream_id == 42
	assert f.msg_type == .data
	assert f.payload == [u8(1), 2, 3]
}

fn test_new_frame_empty_payload() {
	f := new_frame(0, .ping, [])
	assert f.stream_id == 0
	assert f.msg_type == .ping
	assert f.payload.len == 0
}

// --- encode ---

fn test_encode_header_size() {
	f := new_frame(0, .ping, [])
	buf := f.encode()
	assert buf.len == header_size
}

fn test_encode_with_payload() {
	f := new_frame(1, .data, [u8(0xAA), 0xBB])
	buf := f.encode()
	assert buf.len == header_size + 2
}

fn test_encode_big_endian_stream_id() {
	f := new_frame(0x01020304, .data, [])
	buf := f.encode()
	assert buf[0] == 0x01
	assert buf[1] == 0x02
	assert buf[2] == 0x03
	assert buf[3] == 0x04
}

fn test_encode_msg_type_byte() {
	f := new_frame(0, .data_close, [])
	buf := f.encode()
	assert buf[4] == 0x03
}

fn test_encode_big_endian_length() {
	payload := []u8{len: 256}
	f := new_frame(0, .data, payload)
	buf := f.encode()
	// length = 256 = 0x00000100
	assert buf[5] == 0x00
	assert buf[6] == 0x00
	assert buf[7] == 0x01
	assert buf[8] == 0x00
}

fn test_encode_payload_bytes_copied() {
	f := new_frame(0, .data, [u8(0xDE), 0xAD])
	buf := f.encode()
	assert buf[header_size] == 0xDE
	assert buf[header_size + 1] == 0xAD
}

// --- decode ---

fn test_decode_roundtrip_data() {
	original := new_frame(99, .data, 'hello'.bytes())
	encoded := original.encode()
	decoded := decode(encoded)!
	assert decoded.stream_id == 99
	assert decoded.msg_type == .data
	assert decoded.payload == 'hello'.bytes()
}

fn test_decode_roundtrip_empty_payload() {
	original := new_frame(0, .pong, [])
	decoded := decode(original.encode())!
	assert decoded.stream_id == 0
	assert decoded.msg_type == .pong
	assert decoded.payload.len == 0
}

fn test_decode_roundtrip_all_msg_types() {
	types := [MsgType.data_open, .data, .data_close, .ping, .pong, .auth, .auth_ok, .err, .reg_ok]
	for t in types {
		original := new_frame(1, t, [u8(1)])
		decoded := decode(original.encode())!
		assert decoded.msg_type == t
	}
}

fn test_decode_invalid_msg_type_zero() {
	mut buf := []u8{len: header_size}
	buf[4] = 0x00 // invalid: below data_open (0x01)
	if _ := decode(buf) {
		assert false, 'should have returned error for msg_type 0x00'
	}
}

fn test_decode_invalid_msg_type_high() {
	mut buf := []u8{len: header_size}
	buf[4] = 0xFF // invalid: above reg_ok (0x09)
	if _ := decode(buf) {
		assert false, 'should have returned error for msg_type 0xFF'
	}
}

fn test_decode_boundary_msg_types_valid() {
	// 0x01 (data_open) — lowest valid
	mut buf1 := new_frame(0, .data_open, []).encode()
	d1 := decode(buf1)!
	assert d1.msg_type == .data_open

	// 0x09 (reg_ok) — highest valid
	mut buf2 := new_frame(0, .reg_ok, []).encode()
	d2 := decode(buf2)!
	assert d2.msg_type == .reg_ok
}

fn test_decode_too_short_returns_error() {
	short := []u8{len: 5}
	if _ := decode(short) {
		assert false, 'should have returned error'
	}
}

fn test_decode_truncated_payload_returns_error() {
	// Header says 100 bytes but only 2 bytes follow
	mut buf := []u8{len: header_size + 2}
	buf[8] = 100 // length = 100 in last byte (big endian)
	if _ := decode(buf) {
		assert false, 'should have returned error'
	}
}

fn test_decode_max_stream_id() {
	f := new_frame(0xFFFFFFFF, .data, [u8(1)])
	decoded := decode(f.encode())!
	assert decoded.stream_id == 0xFFFFFFFF
}

// --- read_frame via mock reader ---

// MockReader simulates an io.Reader over a byte buffer.
struct MockReader {
mut:
	data []u8
	pos  int
}

fn (mut m MockReader) read(mut buf []u8) !int {
	if m.pos >= m.data.len {
		return io.Eof{}
	}
	n := if m.pos + buf.len > m.data.len { m.data.len - m.pos } else { buf.len }
	for i in 0 .. n {
		buf[i] = m.data[m.pos + i]
	}
	m.pos += n
	return n
}

fn test_read_frame_from_reader() {
	original := new_frame(7, .auth, 'token123'.bytes())
	mut reader := MockReader{
		data: original.encode()
	}
	mut r := io.Reader(reader)
	decoded := read_frame(mut r)!
	assert decoded.stream_id == 7
	assert decoded.msg_type == .auth
	assert decoded.payload.bytestr() == 'token123'
}

fn test_read_frame_empty_payload() {
	original := new_frame(0, .auth_ok, [])
	mut reader := MockReader{
		data: original.encode()
	}
	mut r := io.Reader(reader)
	decoded := read_frame(mut r)!
	assert decoded.stream_id == 0
	assert decoded.msg_type == .auth_ok
	assert decoded.payload.len == 0
}

fn test_read_frame_multiple_frames() {
	f1 := new_frame(1, .data, 'first'.bytes())
	f2 := new_frame(2, .data, 'second'.bytes())
	mut combined := f1.encode()
	combined << f2.encode()
	mut reader := MockReader{
		data: combined
	}
	mut r := io.Reader(reader)

	d1 := read_frame(mut r)!
	assert d1.stream_id == 1
	assert d1.payload.bytestr() == 'first'

	d2 := read_frame(mut r)!
	assert d2.stream_id == 2
	assert d2.payload.bytestr() == 'second'
}

fn test_read_frame_empty_reader_returns_error() {
	mut reader := MockReader{
		data: []
	}
	mut r := io.Reader(reader)
	if _ := read_frame(mut r) {
		assert false, 'should have returned error on empty reader'
	}
}

fn test_read_frame_partial_header_returns_error() {
	mut reader := MockReader{
		data: [u8(0), 0, 0] // only 3 bytes, header needs 9
	}
	mut r := io.Reader(reader)
	if _ := read_frame(mut r) {
		assert false, 'should have returned error on partial header'
	}
}
