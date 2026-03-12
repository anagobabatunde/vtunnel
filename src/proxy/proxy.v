module proxy

import net
import src.acme
import src.transport
import src.tunnel
import src.protocol

// Registry maps subdomain strings to active Tunnels.
@[heap]
pub struct Registry {
pub mut:
	tunnels shared map[string]&tunnel.Tunnel
}

// new_registry creates an empty tunnel registry.
pub fn new_registry() &Registry {
	return &Registry{}
}

// register adds a tunnel for a subdomain.
pub fn (mut r Registry) register(subdomain string, tun &tunnel.Tunnel) {
	lock r.tunnels {
		r.tunnels[subdomain] = tun
	}
}

// unregister removes a tunnel.
pub fn (mut r Registry) unregister(subdomain string) {
	lock r.tunnels {
		r.tunnels.delete(subdomain)
	}
}

// is_registered checks if a subdomain is already taken.
pub fn (mut r Registry) is_registered(subdomain string) bool {
	mut found := false
	rlock r.tunnels {
		if _ := r.tunnels[subdomain] {
			found = true
		}
	}
	return found
}

// get returns the tunnel for a subdomain, or none.
pub fn (mut r Registry) get(subdomain string) ?&tunnel.Tunnel {
	rlock r.tunnels {
		return r.tunnels[subdomain] or { return none }
	}
}

// HttpProxy listens on a public port and routes by Host header.
@[heap]
pub struct HttpProxy {
pub mut:
	registry        &Registry
	port            int
	challenge_store &acme.ChallengeStore = unsafe { nil } // optional ACME challenge store
}

// new_http_proxy creates an HttpProxy bound to the given port.
pub fn new_http_proxy(registry &Registry, port int) &HttpProxy {
	return &HttpProxy{
		registry: registry
		port:     port
	}
}

// set_challenge_store sets the ACME challenge store for HTTP-01 validation.
pub fn (mut p HttpProxy) set_challenge_store(store &acme.ChallengeStore) {
	p.challenge_store = store
}

// listen starts the HTTP proxy listener. Blocking.
pub fn (mut p HttpProxy) listen() ! {
	mut listener := net.listen_tcp(.ip, ':${p.port}')!
	defer {
		listener.close() or {}
	}
	for {
		mut conn := listener.accept() or { continue }
		spawn p.handle_visitor(mut conn)
	}
}

// handle_visitor peeks the Host header, finds the tunnel, and relays.
// Cleanup is done explicitly in correct order to prevent goroutine leaks.
fn (mut p HttpProxy) handle_visitor(mut conn net.TcpConn) {
	// Disable Nagle's algorithm for low-latency relay
	transport.set_nodelay(mut conn)

	// Peek the first chunk to extract Host header
	mut peek := []u8{len: 8192}
	n := conn.read(mut peek) or {
		conn.close() or {}
		return
	}
	peek = peek[..n].clone()

	// Intercept ACME HTTP-01 challenge requests before normal routing
	if p.challenge_store != unsafe { nil } {
		path := extract_path(peek)
		acme_prefix := '/.well-known/acme-challenge/'
		if path.starts_with(acme_prefix) {
			token := path[acme_prefix.len..]
			if key_auth := p.challenge_store.get(token) {
				send_acme_response(mut conn, key_auth)
			} else {
				send_http_error(mut conn, 404, 'challenge token not found')
			}
			conn.close() or {}
			return
		}
	}

	host := extract_host(peek) or {
		send_http_error(mut conn, 400, 'bad request: missing Host header')
		conn.close() or {}
		return
	}
	subdomain := subdomain_from_host(host)

	mut tun := p.registry.get(subdomain) or {
		send_http_error(mut conn, 404, 'tunnel not found: ${subdomain}')
		conn.close() or {}
		return
	}

	// Enforce max concurrent streams per tunnel
	if tun.stream_count() >= tunnel.max_streams {
		send_http_error(mut conn, 503, 'too many connections to ${subdomain}')
		conn.close() or {}
		return
	}

	// Allocate a stream for this visitor
	stream_id := tun.next_stream_id()
	s := tun.open_stream(stream_id)

	// Tell the client a new stream is opening
	tun.send(protocol.new_frame(stream_id, .data_open, subdomain.bytes()))

	// Forward the peeked bytes as the first Data frame
	tun.send(protocol.new_frame(stream_id, .data, peek))

	// Bidirectional relay: visitor <-> stream
	// Spawn the conn->stream direction, block on stream->conn
	spawn tunnel.pipe_conn_to_stream(mut conn, mut tun, s)
	tunnel.pipe_stream_to_conn(mut conn, s)

	// Cleanup in correct order to prevent goroutine leaks:
	// 1. Remove stream — closes s.rx, stops accepting data for this stream
	// 2. Close conn — causes pipe_conn_to_stream's read to fail and exit
	// 3. Notify remote — send data_close so the client cleans up its end
	tun.remove_stream(stream_id)
	conn.close() or {}
	tun.send(protocol.new_frame(stream_id, .data_close, []))
}

// send_http_error writes a minimal HTTP error response and closes the connection.
fn send_http_error(mut conn net.TcpConn, status int, msg string) {
	reason := match status {
		400 { 'Bad Request' }
		404 { 'Not Found' }
		502 { 'Bad Gateway' }
		503 { 'Service Unavailable' }
		else { 'Error' }
	}
	body := '${status} ${reason}: ${msg}\n'
	resp := 'HTTP/1.1 ${status} ${reason}\r\nContent-Type: text/plain\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
	conn.write(resp.bytes()) or {}
}

// extract_host scans raw HTTP bytes for the Host header value.
pub fn extract_host(buf []u8) ?string {
	raw := buf.bytestr()
	// Support both \r\n and \n line endings
	lines := raw.split('\n')
	for line in lines {
		trimmed := line.trim_right('\r')
		lower := trimmed.to_lower()
		if lower.starts_with('host:') {
			return trimmed[5..].trim_space()
		}
	}
	return none
}

// subdomain_from_host extracts the first label from a Host header value.
pub fn subdomain_from_host(host string) string {
	clean := host.split(':')[0]
	parts := clean.split('.')
	if parts.len > 0 {
		return parts[0]
	}
	return host
}

// extract_path extracts the request path from the first line of raw HTTP bytes.
// Returns the path portion (e.g., "/foo/bar" from "GET /foo/bar HTTP/1.1").
pub fn extract_path(buf []u8) string {
	raw := buf.bytestr()
	// Find end of first line
	first_line_end := raw.index('\r\n') or { raw.index('\n') or { raw.len } }
	first_line := raw[..first_line_end]
	// Format: "METHOD /path HTTP/1.1"
	parts := first_line.split(' ')
	if parts.len >= 2 {
		return parts[1]
	}
	return '/'
}

// send_acme_response sends an HTTP 200 response with the ACME key authorization.
fn send_acme_response(mut conn net.TcpConn, key_auth string) {
	resp := 'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: ${key_auth.len}\r\nConnection: close\r\n\r\n${key_auth}'
	conn.write(resp.bytes()) or {}
}
