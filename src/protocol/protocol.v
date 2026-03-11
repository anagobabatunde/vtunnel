module protocol

import encoding.binary
import io

// Wire protocol message types for tunnel communication.
pub enum MsgType as u8 {
	data_open  = 0x01
	data       = 0x02
	data_close = 0x03
	ping       = 0x04
	pong       = 0x05
	auth       = 0x06
	auth_ok    = 0x07
	err        = 0x08
	reg_ok     = 0x09
}

// Frame header: stream_id(4) + msg_type(1) + length(4) = 9 bytes.
pub const header_size = 9

// Maximum allowed payload size (16 MiB) to prevent OOM from malicious frames.
pub const max_payload_size = 16 * 1024 * 1024

// Frame represents a single multiplexed message on the wire.
pub struct Frame {
pub:
	stream_id u32
	msg_type  MsgType
	payload   []u8
}

// new_frame constructs a Frame with the given fields.
pub fn new_frame(stream_id u32, msg_type MsgType, payload []u8) Frame {
	return Frame{
		stream_id: stream_id
		msg_type:  msg_type
		payload:   payload
	}
}

// encode serializes a Frame into a byte slice for transmission.
// Layout: [stream_id u32 BE][msg_type u8][length u32 BE][payload...]
pub fn (f Frame) encode() []u8 {
	payload_len := u32(f.payload.len)
	mut buf := []u8{len: header_size + f.payload.len}
	binary.big_endian_put_u32(mut buf, f.stream_id)
	buf[4] = u8(f.msg_type)
	binary.big_endian_put_u32_at(mut buf, payload_len, 5)
	for i, b in f.payload {
		buf[header_size + i] = b
	}
	return buf
}

// parse_msg_type validates and converts a raw byte to a MsgType.
// Returns an error if the byte is not a known message type.
fn parse_msg_type(b u8) !MsgType {
	if b < u8(MsgType.data_open) || b > u8(MsgType.reg_ok) {
		return error('unknown msg_type: 0x${b:02x}')
	}
	return unsafe { MsgType(b) }
}

// decode parses a Frame from a complete raw byte slice (header + payload).
pub fn decode(raw []u8) !Frame {
	if raw.len < header_size {
		return error('frame too short: ${raw.len} bytes')
	}
	stream_id := binary.big_endian_u32(raw[0..4])
	msg_type := parse_msg_type(raw[4])!
	length := int(binary.big_endian_u32(raw[5..9]))
	if raw.len < header_size + length {
		return error('frame payload truncated: want ${length}, have ${raw.len - header_size}')
	}
	payload := raw[header_size..header_size + length].clone()
	return Frame{
		stream_id: stream_id
		msg_type:  msg_type
		payload:   payload
	}
}

// read_exact reads exactly n bytes from reader into buf.
fn read_exact(mut reader io.Reader, mut buf []u8) ! {
	mut total := 0
	for total < buf.len {
		n := reader.read(mut buf[total..]) or { return err }
		if n == 0 {
			return error('connection closed')
		}
		total += n
	}
}

// read_frame reads exactly one frame from an io.Reader.
// Reads the 9-byte header first, then reads the declared payload length.
pub fn read_frame(mut reader io.Reader) !Frame {
	mut hdr := []u8{len: header_size}
	read_exact(mut reader, mut hdr)!
	length := int(binary.big_endian_u32(hdr[5..9]))
	if length < 0 || length > max_payload_size {
		return error('frame payload too large: ${length} bytes')
	}
	mut payload := []u8{len: length}
	if length > 0 {
		read_exact(mut reader, mut payload)!
	}
	stream_id := binary.big_endian_u32(hdr[0..4])
	msg_type := parse_msg_type(hdr[4])!
	return Frame{
		stream_id: stream_id
		msg_type:  msg_type
		payload:   payload
	}
}
