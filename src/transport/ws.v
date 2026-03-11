module transport

import net.websocket
import time

// Default WebSocket timeouts (matches tunnel.idle_timeout).
const ws_timeout = 60 * time.second

// WsTransport wraps a WebSocket client and implements the Transport interface.
// Bridges the callback-driven WebSocket API to the synchronous read/write Transport model
// using a channel-based buffering adapter.
@[heap]
pub struct WsTransport {
mut:
	ws  &websocket.Client // underlying WS client (write + close)
	rx  chan []u8         // incoming message payloads from on_message callback
	buf []u8              // leftover bytes from partial reads
}

// WsClientCtx holds per-client state for the server-side WebSocket message callback.
@[heap]
pub struct WsClientCtx {
pub:
	rx chan []u8
}

// new_ws_client creates a client-side WebSocket transport.
// Connects to the server at addr (host:port) using ws:// or wss:// depending on tls flag.
pub fn new_ws_client(addr string, tls bool) !&WsTransport {
	scheme := if tls { 'wss' } else { 'ws' }
	url := '${scheme}://${addr}/tunnel'

	rx := chan []u8{cap: 128}
	ctx := &WsClientCtx{
		rx: rx
	}

	mut ws := websocket.new_client(url, websocket.ClientOpt{
		read_timeout:  ws_timeout
		write_timeout: ws_timeout
	})!

	ws.on_message_ref(ws_client_on_message, voidptr(ctx))

	ws.connect()!
	spawn ws.listen()

	return &WsTransport{
		ws:  ws
		rx:  rx
		buf: []u8{}
	}
}

// ws_client_on_message handles incoming WebSocket messages for a client transport.
fn ws_client_on_message(mut c websocket.Client, msg &websocket.Message, ctx_ptr voidptr) ! {
	if msg.opcode == .binary_frame {
		ctx := unsafe { &WsClientCtx(ctx_ptr) }
		data := msg.payload.clone()
		ctx.rx.try_push(&data)
	}
}

// new_ws_server_transport creates a server-side WebSocket transport from an already-connected
// WebSocket client reference and its message channel.
pub fn new_ws_server_transport(ws_client &websocket.Client, rx chan []u8) &WsTransport {
	return &WsTransport{
		ws:  ws_client
		rx:  rx
		buf: []u8{}
	}
}

// read implements Transport. Reads bytes from the internal buffer or blocks on the rx channel
// for the next WebSocket message. Handles partial reads with internal buffering.
pub fn (mut t WsTransport) read(mut buf []u8) !int {
	// Serve leftover bytes from a previous partial read
	if t.buf.len > 0 {
		n := if t.buf.len < buf.len { t.buf.len } else { buf.len }
		for i in 0 .. n {
			buf[i] = t.buf[i]
		}
		t.buf = t.buf[n..].clone()
		return n
	}

	// Block on the channel for the next message
	data := <-t.rx or { return error('connection closed') }

	n := if data.len < buf.len { data.len } else { buf.len }
	for i in 0 .. n {
		buf[i] = data[i]
	}

	// Store remainder if message exceeds buf capacity
	if data.len > buf.len {
		t.buf = data[buf.len..].clone()
	}

	return n
}

// write implements Transport. Sends data as a single WebSocket binary frame.
pub fn (mut t WsTransport) write(data []u8) !int {
	return t.ws.write(data, .binary_frame)
}

// close implements Transport. Sends a WebSocket close frame and shuts down the channel.
pub fn (mut t WsTransport) close() ! {
	t.rx.close()
	t.ws.close(1000, '') or {}
}
