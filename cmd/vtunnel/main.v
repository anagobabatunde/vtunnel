module main

import os
import net
import net.mbedtls
import net.websocket
import crypto.ecdsa
import rand
import time
import src.acme
import src.auth
import src.config
import src.hosted
import src.slog
import src.tunnel
import src.protocol
import src.proxy
import src.transport

fn main() {
	cmd := config.parse_command()
	match cmd {
		.http, .tcp { run_client() }
		.server { run_server() }
		.token { run_token() }
		.auth { run_auth() }
		.help { config.print_usage() }
	}
}

// --- Client (http/tcp) ---

// run_client starts the tunnel client with reconnection logic.
fn run_client() {
	cfg := config.parse_client_args()

	logger := slog.new('client', slog.parse_level(cfg.log_level), slog.parse_format(cfg.log_format))

	os.signal_opt(.int, fn (_ os.Signal) {
		println('\nvtunnel: shutting down (SIGINT)...')
		exit(0)
	}) or {}
	os.signal_opt(.term, fn (_ os.Signal) {
		println('vtunnel: shutting down (SIGTERM)...')
		exit(0)
	}) or {}

	mut backoff_ms := i64(1000)
	max_backoff_ms := i64(30000)

	for {
		start_unix := time.now().unix()

		connect_and_run(cfg, logger) or {
			msg := err.msg()
			logger.error(msg)
			if msg.starts_with('auth failed') || msg.starts_with('registration failed') {
				return
			}
		}

		elapsed := time.now().unix() - start_unix
		if elapsed > 60 {
			backoff_ms = 1000
		}

		jitter_range := backoff_ms / 4
		jitter := if jitter_range > 0 {
			rand.i64_in_range(-jitter_range, jitter_range + 1) or { 0 }
		} else {
			i64(0)
		}
		wait_ms := backoff_ms + jitter

		logger.info('reconnecting in ${wait_ms}ms')
		time.sleep(wait_ms * time.millisecond)

		backoff_ms = if backoff_ms * 2 > max_backoff_ms {
			max_backoff_ms
		} else {
			backoff_ms * 2
		}
	}
}

// connect_and_run establishes a tunnel connection, performs auth/registration,
// and runs the read/write loops until the connection drops.
fn connect_and_run(cfg config.ClientConfig, logger &slog.Logger) ! {
	logger.info('connecting to ${cfg.server_addr}')

	mut tun := create_tunnel(cfg, logger)!

	if cfg.auth_token.len > 0 && !cfg.tls {
		logger.warn('sending auth token without TLS (plaintext)')
	}
	if cfg.auth_token.len > 0 {
		auth_frame := protocol.new_frame(0, .auth, cfg.auth_token.bytes())
		tun.write_raw(auth_frame.encode()) or {
			tun.close()
			return error('failed to send auth frame: ${err}')
		}
		resp := tun.read_frame() or {
			tun.close()
			return error('failed to read auth response: ${err}')
		}
		if resp.msg_type == .err {
			tun.close()
			return error('auth failed: ${resp.payload.bytestr()}')
		}
		if resp.msg_type != .auth_ok {
			tun.close()
			return error('unexpected response: expected auth_ok, got ${resp.msg_type}')
		}
	}

	reg := protocol.new_frame(0, .data_open, cfg.subdomain.bytes())
	tun.write_raw(reg.encode()) or {
		tun.close()
		return error('failed to send register frame: ${err}')
	}

	reg_resp := tun.read_frame() or {
		tun.close()
		return error('failed to read registration response: ${err}')
	}
	if reg_resp.msg_type == .err {
		tun.close()
		return error('registration failed: ${reg_resp.payload.bytestr()}')
	}
	if reg_resp.msg_type != .reg_ok {
		tun.close()
		return error('unexpected response: expected reg_ok, got ${reg_resp.msg_type}')
	}

	assigned := reg_resp.payload.bytestr()

	// Extract the base domain from the server address for display
	server_host := cfg.server_addr.split(':')[0]
	tunnel_url := '${assigned}.${server_host}'

	println('')
	println('  tunnel ready: https://${tunnel_url}')
	println('  forwarding:   https://${tunnel_url} -> ${cfg.local_addr}')
	println('')
	logger.info('connected to ${cfg.server_addr}')
	logger.info('forwarding ${assigned} -> ${cfg.local_addr}')

	spawn tun.run_write_loop()
	spawn tun.run_ping_loop()

	tun.run_read_loop(fn [mut tun, cfg, logger] (stream_id u32, payload []u8) {
		s := tun.open_stream(stream_id)
		spawn handle_stream(mut tun, s, cfg.local_addr, logger)
	})

	tun.close()
	logger.info('disconnected')
}

// create_tunnel builds the appropriate transport and wraps it in a Tunnel.
fn create_tunnel(cfg config.ClientConfig, logger &slog.Logger) !&tunnel.Tunnel {
	if cfg.ws {
		ws_mode := if cfg.tls { ' (wss)' } else { '' }
		logger.info('connecting via WebSocket${ws_mode}')
		t := transport.new_ws_client(cfg.server_addr, cfg.tls)!
		return tunnel.new(t)
	}

	if cfg.tls {
		parts := cfg.server_addr.split(':')
		host := parts[0]
		port := if parts.len > 1 { parts[1].int() } else { 443 }
		if cfg.tls_ca.len > 0 {
			logger.info('using TLS', detail: 'ca: ${cfg.tls_ca}')
		} else {
			logger.warn('TLS without --tls-ca, server cert not verified')
		}
		t := transport.new_tls_client(host, port, cfg.tls_ca)!
		return tunnel.new(t)
	}

	mut conn := net.dial_tcp(cfg.server_addr)!
	mut tcp := transport.new_tcp(conn)
	tcp.set_read_timeout(tunnel.idle_timeout)
	return tunnel.new(tcp)
}

// handle_stream connects to the local service and relays data for one stream.
fn handle_stream(mut tun tunnel.Tunnel, s &tunnel.Stream, local_addr string, logger &slog.Logger) {
	mut local := net.dial_tcp(local_addr) or {
		logger.error('failed to connect to local service',
			err:       '${err}'
			stream_id: int(s.id)
			detail:    local_addr
		)
		tun.send(protocol.new_frame(s.id, .data_close, []))
		tun.remove_stream(s.id)
		return
	}

	spawn tunnel.pipe_conn_to_stream(mut local, mut tun, s)
	tunnel.pipe_stream_to_conn(mut local, s)

	tun.remove_stream(s.id)
	local.close() or {}
	tun.send(protocol.new_frame(s.id, .data_close, []))
}

// --- Server ---

// run_server starts the relay server.
fn run_server() {
	cfg := config.parse_server_args()

	logger := slog.new('server', slog.parse_level(cfg.log_level), slog.parse_format(cfg.log_format))

	os.signal_opt(.int, fn (_ os.Signal) {
		println('\nvtunnel: shutting down (SIGINT)...')
		exit(0)
	}) or {}
	os.signal_opt(.term, fn (_ os.Signal) {
		println('vtunnel: shutting down (SIGTERM)...')
		exit(0)
	}) or {}

	// Handle legacy --generate-token flag
	if cfg.generate_token {
		run_token_generate(cfg.token_file)
		return
	}

	// Build authenticator based on server mode
	authenticator, database := build_authenticator(cfg, logger)

	mut tls_cert := cfg.tls_cert
	mut tls_key := cfg.tls_key

	mut registry := proxy.new_registry()
	mut http_proxy := proxy.new_http_proxy(registry, cfg.http_port)

	if cfg.acme {
		acme_log := logger.with_component('acme')

		challenge_store := acme.new_challenge_store()
		http_proxy.set_challenge_store(challenge_store)

		spawn http_proxy.listen()

		_, init_privkey := ecdsa.generate_key() or {
			acme_log.error('failed to generate initial key', err: '${err}')
			return
		}

		mut acme_client := acme.new_client(cfg.domain, cfg.acme_email, cfg.acme_dir, cfg.acme_staging,
			challenge_store, init_privkey)
		acme_client.logger = acme_log

		acme_client.discover() or {
			acme_log.error('failed to discover directory', err: '${err}')
			return
		}

		acme_client.register_or_load_account() or {
			acme_log.error('failed to register/load account', err: '${err}')
			return
		}

		cert_info := acme_client.obtain_certificate() or {
			acme_log.error('failed to obtain certificate', err: '${err}')
			return
		}

		tls_cert = cert_info.cert_path
		tls_key = cert_info.key_path
		acme_log.info('using certificate', detail: tls_cert)

		spawn acme_client.run_renewal_loop(12 * time.hour, 30 * 24 * time.hour, fn (info acme.CertInfo) {
			println('acme: certificate renewed, restart server to use new cert')
			println('acme: new cert: ${info.cert_path}')
		})
	} else {
		spawn http_proxy.listen()
	}

	tls_enabled := tls_cert.len > 0 && tls_key.len > 0

	// Start management API in hosted mode
	if cfg.mode == 'hosted' {
		if database != unsafe { nil } {
			mut api := hosted.new_api_server(database, cfg.api_key, cfg.api_port)
			spawn api.listen()
			logger.info('management API started', detail: ':${cfg.api_port}')
		}
	}

	if cfg.ws_port > 0 {
		spawn start_ws_listener(mut registry, authenticator, cfg.ws_port, logger)
	}

	if tls_enabled {
		logger.info('TLS enabled', detail: tls_cert)
		mut ssl_listener := mbedtls.new_ssl_listener(':${cfg.port}', mbedtls.SSLConnectConfig{
			cert:     tls_cert
			cert_key: tls_key
		}) or {
			logger.error('failed to start TLS listener', err: '${err}', detail: ':${cfg.port}')
			return
		}
		defer {
			ssl_listener.shutdown() or {}
		}
		logger.info('listening',
			detail: 'control(tls) on :${cfg.port}, http on :${cfg.http_port}, domain ${cfg.domain}'
		)

		for {
			ssl_conn := ssl_listener.accept() or { continue }
			mut t := transport.new_tls(ssl_conn)
			t.set_read_timeout(tunnel.idle_timeout)
			mut tun := tunnel.new(t)
			spawn handle_control(mut tun, mut registry, authenticator, logger)
		}
	} else {
		mut listener := net.listen_tcp(.ip, '${cfg.host}:${cfg.port}') or {
			logger.error('failed to listen', err: '${err}', detail: '${cfg.host}:${cfg.port}')
			return
		}
		defer {
			listener.close() or {}
		}
		logger.info('listening',
			detail: 'control on :${cfg.port}, http on :${cfg.http_port}, domain ${cfg.domain}'
		)

		for {
			conn := listener.accept() or { continue }
			mut tcp := transport.new_tcp(conn)
			tcp.set_read_timeout(tunnel.idle_timeout)
			mut tun := tunnel.new(tcp)
			spawn handle_control(mut tun, mut registry, authenticator, logger)
		}
	}
}

// build_authenticator creates the appropriate authenticator based on the server mode.
// Returns the authenticator and optionally a database reference (for hosted mode).
fn build_authenticator(cfg config.ServerConfig, logger &slog.Logger) (auth.Authenticator, &hosted.Database) {
	if cfg.mode == 'hosted' {
		database := hosted.open_database(cfg.db_path) or {
			logger.error('failed to open database', err: '${err}', detail: cfg.db_path)
			exit(1)
		}
		logger.info('hosted mode enabled', detail: 'db: ${cfg.db_path}')
		authenticator := auth.Authenticator(hosted.new_db_authenticator(database))
		return authenticator, database
	}

	// Standalone mode — file-based tokens or no auth
	if cfg.token_file.len > 0 {
		tokens := auth.load_tokens(cfg.token_file) or {
			logger.error('failed to load tokens', err: '${err}', detail: cfg.token_file)
			exit(1)
		}
		logger.info('auth enabled, ${tokens.len} token(s) loaded')
		authenticator := auth.Authenticator(auth.new_file_authenticator(tokens))
		return authenticator, unsafe { nil }
	}

	logger.warn('no --token-file set, auth disabled (dev mode)')
	authenticator := auth.Authenticator(auth.new_no_authenticator())
	return authenticator, unsafe { nil }
}

// handle_control manages a single tunnel client control connection.
// Uses the Authenticator interface for both standalone and hosted modes.
fn handle_control(mut tun tunnel.Tunnel, mut registry proxy.Registry, authenticator auth.Authenticator, logger &slog.Logger) {
	ctrl := logger.with_component('control')
	defer {
		tun.close()
	}

	// Always attempt authentication — NoAuthenticator handles the no-auth case
	f := tun.read_frame() or {
		ctrl.error('failed to read auth frame', err: '${err}')
		return
	}

	// If the client sends an auth frame, validate it
	if f.msg_type == .auth {
		token := f.payload.bytestr()
		authenticator.validate(token) or {
			err_frame := protocol.new_frame(0, .err, 'invalid token'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.error('invalid token', token: auth.redact_token(token))
			return
		}
		ok_frame := protocol.new_frame(0, .auth_ok, [])
		tun.write_raw(ok_frame.encode()) or {
			ctrl.error('failed to send auth_ok', err: '${err}')
			return
		}
		ctrl.info('authenticated', token: token)

		// Read the next frame (subdomain registration)
		reg_f := tun.read_frame() or {
			ctrl.error('failed to read register frame', err: '${err}')
			return
		}
		register_subdomain(mut tun, mut registry, reg_f, ctrl)
		return
	}

	// Client didn't send an auth frame — reject if auth is required
	if authenticator.requires_auth() {
		err_frame := protocol.new_frame(0, .err, 'authentication required'.bytes())
		tun.write_raw(err_frame.encode()) or {}
		ctrl.error('expected auth frame', detail: '${f.msg_type}')
		return
	}

	// No auth required (dev mode) — treat the first frame as registration directly
	register_subdomain(mut tun, mut registry, f, ctrl)
}

// register_subdomain handles the subdomain registration frame and starts the tunnel.
// If the client sends an empty subdomain, the server auto-assigns a random one.
fn register_subdomain(mut tun tunnel.Tunnel, mut registry proxy.Registry, f protocol.Frame, ctrl &slog.Logger) {
	if f.msg_type != .data_open {
		ctrl.error('expected data_open', detail: '${f.msg_type}')
		return
	}
	requested := f.payload.bytestr()

	// Auto-assign a random subdomain if client didn't request one
	mut subdomain := requested
	if subdomain == '' {
		for attempt in 0 .. 5 {
			candidate := auth.generate_random_subdomain() or {
				ctrl.error('failed to generate subdomain', err: '${err}')
				return
			}
			if !registry.is_registered(candidate) {
				subdomain = candidate
				break
			}
			ctrl.warn('auto-assign collision, retrying',
				subdomain: candidate
				detail:    'attempt ${attempt + 1}/5'
			)
		}
		if subdomain == '' {
			err_frame := protocol.new_frame(0, .err, 'failed to auto-assign subdomain'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.error('all auto-assign attempts failed')
			return
		}
		ctrl.info('auto-assigned subdomain', subdomain: subdomain)
	} else {
		// Validate client-requested subdomain
		auth.validate_subdomain(subdomain) or {
			err_frame := protocol.new_frame(0, .err, 'invalid subdomain: ${err}'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.error('invalid subdomain', err: '${err}', subdomain: subdomain)
			return
		}
		if registry.is_registered(subdomain) {
			err_frame := protocol.new_frame(0, .err, 'subdomain already in use: ${subdomain}'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.warn('subdomain collision', subdomain: subdomain)
			return
		}
	}

	registry.register(subdomain, tun)
	defer {
		registry.unregister(subdomain)
	}

	reg_ok_frame := protocol.new_frame(0, .reg_ok, subdomain.bytes())
	tun.write_raw(reg_ok_frame.encode()) or {
		ctrl.error('failed to send reg_ok', err: '${err}', subdomain: subdomain)
		return
	}
	ctrl.info('tunnel registered', subdomain: subdomain)

	spawn tun.run_write_loop()
	spawn tun.run_ping_loop()
	tun.run_read_loop(fn (stream_id u32, payload []u8) {
	})

	ctrl.info('tunnel disconnected', subdomain: subdomain)
}

// --- WebSocket listener ---

struct WsEvent {
	client_id  string
	payload    []u8
	is_close   bool
	client_ptr voidptr
}

@[heap]
struct WsDispatchCtx {
	events chan WsEvent
}

fn start_ws_listener(mut registry proxy.Registry, authenticator auth.Authenticator, port int, logger &slog.Logger) {
	events := chan WsEvent{cap: 256}
	ctx := &WsDispatchCtx{
		events: events
	}

	mut ws_server := websocket.new_server(.ip, port, '/tunnel')

	ws_server.on_message_ref(ws_server_on_message, voidptr(ctx))
	ws_server.on_close_ref(ws_server_on_close, voidptr(ctx))

	spawn ws_dispatch_loop(events, mut registry, authenticator, logger)

	logger.info('websocket listener started', detail: ':${port}')
	ws_server.listen() or { logger.error('websocket listener error', err: '${err}') }
}

fn ws_server_on_message(mut c websocket.Client, msg &websocket.Message, ptr voidptr) ! {
	if msg.opcode != .binary_frame {
		return
	}
	ctx := unsafe { &WsDispatchCtx(ptr) }
	ev := WsEvent{
		client_id:  c.id
		payload:    msg.payload.clone()
		client_ptr: voidptr(c)
	}
	ctx.events.try_push(&ev)
}

fn ws_server_on_close(mut c websocket.Client, code int, reason string, ptr voidptr) ! {
	ctx := unsafe { &WsDispatchCtx(ptr) }
	ev := WsEvent{
		client_id: c.id
		is_close:  true
	}
	ctx.events.try_push(&ev)
}

fn ws_dispatch_loop(events chan WsEvent, mut registry proxy.Registry, authenticator auth.Authenticator, logger &slog.Logger) {
	mut routes := map[string]chan []u8{}

	for {
		ev := <-events or { break }

		if ev.is_close {
			if rx := routes[ev.client_id] {
				rx.close()
			}
			routes.delete(ev.client_id)
			continue
		}

		if ev.client_id in routes {
			if rx := routes[ev.client_id] {
				payload := ev.payload
				rx.try_push(&payload)
			}
			continue
		}

		rx := chan []u8{cap: 128}
		routes[ev.client_id] = rx
		first_payload := ev.payload
		rx.try_push(&first_payload)

		ws_client := unsafe { &websocket.Client(ev.client_ptr) }
		mut t := transport.new_ws_server_transport(ws_client, rx)
		mut tun := tunnel.new(t)
		spawn handle_control(mut tun, mut registry, authenticator, logger)
	}
}

// --- Token ---

// run_token handles the "vtunnel token" subcommand.
fn run_token() {
	cfg := config.parse_token_args()
	if cfg.action != 'generate' {
		eprintln('usage: vtunnel token generate --token-file <path>')
		exit(1)
	}
	run_token_generate(cfg.token_file)
}

// run_token_generate creates a token, saves it, and prints it.
fn run_token_generate(token_file string) {
	if token_file == '' {
		eprintln('--token-file <path> is required')
		exit(1)
	}
	token := auth.generate_token() or {
		eprintln('failed to generate token: ${err}')
		exit(1)
	}
	auth.save_token(token_file, token) or {
		eprintln('failed to save token: ${err}')
		exit(1)
	}
	println('generated token: ${token}')
	println('saved to: ${token_file}')
}

// --- Auth ---

// run_auth handles the "vtunnel auth <token>" subcommand.
// Saves the API key and server address to ~/.vtunnel/config.json.
fn run_auth() {
	args := os.args[2..] // skip binary name and "auth"
	if args.len == 0 || args[0].starts_with('-') {
		println('vtunnel auth — save your API key for the hosted service

Usage:
  vtunnel auth <api-key> [--server <host:port>]

Examples:
  vtunnel auth vtk_abc123def456...
  vtunnel auth vtk_abc123... --server my-server.com:8080

This saves your credentials to ~/.vtunnel/config.json so you can
simply run "vtunnel http 3000" without any extra flags.')
		return
	}

	token := args[0]
	mut server := config.default_server

	// Parse optional --server flag
	mut i := 1
	for i < args.len {
		if args[i] == '--server' && i + 1 < args.len {
			server = args[i + 1]
			i += 2
		} else {
			i++
		}
	}

	config.save_config(server, token) or {
		eprintln('failed to save config: ${err}')
		exit(1)
	}

	println('Authenticated successfully!')
	println('')
	println('  Server: ${server}')
	redacted := auth.redact_token(token)
	println('  Token:  ${redacted}')
	println('  Saved:  ${config.config_dir()}/config.json')
	println('')
	println('You can now run:')
	println('  vtunnel http 3000')
}
