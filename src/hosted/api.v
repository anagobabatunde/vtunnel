module hosted

import net
import json

// ApiServer serves the management REST API for the hosted mode.
// Protected by a server-to-server API key in the Authorization header.
@[heap]
pub struct ApiServer {
	database &Database
	api_key  string // server-to-server secret
	port     int
}

// ApiRequest represents a parsed HTTP request.
struct ApiRequest {
	method  string
	path    string
	body    string
	headers map[string]string
}

// new_api_server creates a management API server.
pub fn new_api_server(database &Database, api_key string, port int) &ApiServer {
	return &ApiServer{
		database: database
		api_key:  api_key
		port:     port
	}
}

// listen starts the API server. Blocking.
pub fn (mut s ApiServer) listen() ! {
	mut listener := net.listen_tcp(.ip, ':${s.port}') or {
		return error('api: failed to listen on :${s.port}: ${err}')
	}
	defer {
		listener.close() or {}
	}
	for {
		mut conn := listener.accept() or { continue }
		spawn s.handle_request(mut conn)
	}
}

// handle_request parses an HTTP request and routes to the appropriate handler.
fn (s &ApiServer) handle_request(mut conn net.TcpConn) {
	defer {
		conn.close() or {}
	}

	req := parse_http_request(mut conn) or {
		send_json_error(mut conn, 400, 'bad request')
		return
	}

	// Authenticate with server-to-server key
	if s.api_key.len > 0 {
		auth_header := req.headers['authorization'] or { '' }
		expected := 'Bearer ${s.api_key}'
		if auth_header != expected {
			send_json_error(mut conn, 401, 'unauthorized')
			return
		}
	}

	// Route the request
	s.route(mut conn, req)
}

// route dispatches to the correct handler based on method + path.
fn (s &ApiServer) route(mut conn net.TcpConn, req ApiRequest) {
	parts := req.path.trim_left('/').split('/')

	// /api/v1/users
	if parts.len >= 3 && parts[0] == 'api' && parts[1] == 'v1' && parts[2] == 'users' {
		if parts.len == 3 {
			if req.method == 'POST' {
				s.handle_create_user(mut conn, req)
				return
			}
		}
		if parts.len == 4 {
			user_id := parts[3]
			if req.method == 'GET' {
				s.handle_get_user(mut conn, user_id)
				return
			}
			if req.method == 'PUT' {
				s.handle_update_user(mut conn, user_id, req)
				return
			}
		}
		// /api/v1/users/:id/keys
		if parts.len >= 5 && parts[4] == 'keys' {
			user_id := parts[3]
			if parts.len == 5 {
				if req.method == 'POST' {
					s.handle_create_key(mut conn, user_id, req)
					return
				}
				if req.method == 'GET' {
					s.handle_list_keys(mut conn, user_id)
					return
				}
			}
			// /api/v1/users/:id/keys/:kid
			if parts.len == 6 && req.method == 'DELETE' {
				key_id := parts[5]
				s.handle_revoke_key(mut conn, key_id)
				return
			}
		}
		// /api/v1/users/:id/usage
		if parts.len == 5 && parts[4] == 'usage' && req.method == 'GET' {
			user_id := parts[3]
			s.handle_get_usage(mut conn, user_id)
			return
		}
	}

	send_json_error(mut conn, 404, 'not found')
}

// --- Handlers ---

fn (s &ApiServer) handle_create_user(mut conn net.TcpConn, req ApiRequest) {
	data := json.decode(CreateUserRequest, req.body) or {
		send_json_error(mut conn, 400, 'invalid json: ${err}')
		return
	}
	user := s.database.create_user(data.email, data.name) or {
		send_json_error(mut conn, 409, '${err}')
		return
	}
	send_json_response(mut conn, 201, json.encode(user))
}

fn (s &ApiServer) handle_get_user(mut conn net.TcpConn, user_id string) {
	user := s.database.get_user(user_id) or {
		send_json_error(mut conn, 404, '${err}')
		return
	}
	send_json_response(mut conn, 200, json.encode(user))
}

fn (s &ApiServer) handle_update_user(mut conn net.TcpConn, user_id string, req ApiRequest) {
	data := json.decode(UpdateUserRequest, req.body) or {
		send_json_error(mut conn, 400, 'invalid json: ${err}')
		return
	}
	if data.tier.len > 0 {
		s.database.update_tier(user_id, data.tier) or {
			send_json_error(mut conn, 500, '${err}')
			return
		}
	}
	user := s.database.get_user(user_id) or {
		send_json_error(mut conn, 404, '${err}')
		return
	}
	send_json_response(mut conn, 200, json.encode(user))
}

fn (s &ApiServer) handle_create_key(mut conn net.TcpConn, user_id string, req ApiRequest) {
	data := json.decode(CreateKeyRequest, req.body) or {
		send_json_error(mut conn, 400, 'invalid json: ${err}')
		return
	}
	name := if data.name.len > 0 { data.name } else { 'default' }
	result := s.database.create_api_key(user_id, name) or {
		send_json_error(mut conn, 500, '${err}')
		return
	}
	send_json_response(mut conn, 201, json.encode(result))
}

fn (s &ApiServer) handle_list_keys(mut conn net.TcpConn, user_id string) {
	keys := s.database.list_api_keys(user_id) or {
		send_json_error(mut conn, 500, '${err}')
		return
	}
	send_json_response(mut conn, 200, json.encode(keys))
}

fn (s &ApiServer) handle_revoke_key(mut conn net.TcpConn, key_id string) {
	s.database.revoke_api_key(key_id) or {
		send_json_error(mut conn, 500, '${err}')
		return
	}
	send_json_response(mut conn, 200, '{"ok":true}')
}

fn (s &ApiServer) handle_get_usage(mut conn net.TcpConn, user_id string) {
	usage := s.database.get_monthly_usage(user_id) or {
		send_json_error(mut conn, 500, '${err}')
		return
	}
	send_json_response(mut conn, 200, json.encode(usage))
}

// --- Request/Response types ---

struct CreateUserRequest {
	email string
	name  string
}

struct UpdateUserRequest {
	tier string
}

struct CreateKeyRequest {
	name string
}

// --- HTTP helpers ---

// parse_http_request reads a raw HTTP request from a connection.
fn parse_http_request(mut conn net.TcpConn) !ApiRequest {
	mut buf := []u8{len: 65536}
	n := conn.read(mut buf) or { return error('failed to read request') }
	raw := buf[..n].bytestr()

	// Split headers and body
	header_end := raw.index('\r\n\r\n') or { raw.len }
	header_section := raw[..header_end]
	body := if header_end + 4 < raw.len { raw[header_end + 4..] } else { '' }

	lines := header_section.split('\r\n')
	if lines.len == 0 {
		return error('empty request')
	}

	// Parse request line: "METHOD /path HTTP/1.1"
	request_line := lines[0].split(' ')
	if request_line.len < 2 {
		return error('invalid request line')
	}

	method := request_line[0]
	path := request_line[1]

	// Parse headers
	mut headers := map[string]string{}
	for i in 1 .. lines.len {
		colon := lines[i].index(':') or { continue }
		key := lines[i][..colon].to_lower().trim_space()
		value := lines[i][colon + 1..].trim_space()
		headers[key] = value
	}

	return ApiRequest{
		method:  method
		path:    path
		body:    body
		headers: headers
	}
}

// send_json_response writes a JSON HTTP response.
fn send_json_response(mut conn net.TcpConn, status int, body string) {
	reason := match status {
		200 { 'OK' }
		201 { 'Created' }
		204 { 'No Content' }
		else { 'OK' }
	}
	resp := 'HTTP/1.1 ${status} ${reason}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
	conn.write(resp.bytes()) or {}
}

// send_json_error writes a JSON error response.
fn send_json_error(mut conn net.TcpConn, status int, msg string) {
	reason := match status {
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		404 { 'Not Found' }
		409 { 'Conflict' }
		500 { 'Internal Server Error' }
		else { 'Error' }
	}
	body := '{"error":"${msg}"}'
	resp := 'HTTP/1.1 ${status} ${reason}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
	conn.write(resp.bytes()) or {}
}
