module main

import os
import net
import net.mbedtls
import net.websocket
import crypto.ecdsa
import time
import src.acme
import src.auth
import src.config
import src.slog
import src.tunnel
import src.protocol
import src.proxy
import src.transport

fn main() {
	cfg := config.parse_server_args()

	// Create logger from config
	logger := slog.new('server', slog.parse_level(cfg.log_level), slog.parse_format(cfg.log_format))

	// Install signal handlers for graceful shutdown
	// Note: signal handlers cannot capture logger (V closure limitation)
	os.signal_opt(.int, fn (_ os.Signal) {
		println('\nvtunnel-server: shutting down (SIGINT)...')
		exit(0)
	}) or {}
	os.signal_opt(.term, fn (_ os.Signal) {
		println('vtunnel-server: shutting down (SIGTERM)...')
		exit(0)
	}) or {}

	// Handle --generate-token: create a token, save it, print it, exit
	// Uses println/eprintln directly (CLI tool output, not runtime logging)
	if cfg.generate_token {
		if cfg.token_file.len == 0 {
			eprintln('--generate-token requires --token-file <path>')
			return
		}
		token := auth.generate_token() or {
			eprintln('failed to generate token: ${err}')
			return
		}
		auth.save_token(cfg.token_file, token) or {
			eprintln('failed to save token: ${err}')
			return
		}
		println('generated token: ${token}')
		println('saved to: ${cfg.token_file}')
		return
	}

	// Load tokens if token file is configured
	mut tokens := []string{}
	auth_enabled := cfg.token_file.len > 0
	if auth_enabled {
		tokens = auth.load_tokens(cfg.token_file) or {
			logger.error('failed to load tokens', err: '${err}', detail: cfg.token_file)
			return
		}
		logger.info('auth enabled, ${tokens.len} token(s) loaded')
	} else {
		logger.warn('no --token-file set, auth disabled (dev mode)')
	}

	mut tls_cert := cfg.tls_cert
	mut tls_key := cfg.tls_key

	mut registry := proxy.new_registry()
	mut http_proxy := proxy.new_http_proxy(registry, cfg.http_port)

	// ACME auto-TLS setup
	if cfg.acme {
		acme_log := logger.with_component('acme')

		challenge_store := acme.new_challenge_store()
		http_proxy.set_challenge_store(challenge_store)

		// Start HTTP proxy early so ACME HTTP-01 challenges can be served
		spawn http_proxy.listen()

		// Generate a temporary key for initial client construction
		_, init_privkey := ecdsa.generate_key() or {
			acme_log.error('failed to generate initial key', err: '${err}')
			return
		}

		mut acme_client := acme.new_client(cfg.domain, cfg.acme_email, cfg.acme_dir, cfg.acme_staging,
			challenge_store, init_privkey)
		acme_client.logger = acme_log

		// Discover ACME directory endpoints
		acme_client.discover() or {
			acme_log.error('failed to discover directory', err: '${err}')
			return
		}

		// Register or load existing ACME account
		acme_client.register_or_load_account() or {
			acme_log.error('failed to register/load account', err: '${err}')
			return
		}

		// Obtain or renew certificate
		cert_info := acme_client.obtain_certificate() or {
			acme_log.error('failed to obtain certificate', err: '${err}')
			return
		}

		tls_cert = cert_info.cert_path
		tls_key = cert_info.key_path
		acme_log.info('using certificate', detail: tls_cert)

		// Spawn renewal loop in background (check every 12h, renew 30d before expiry)
		spawn acme_client.run_renewal_loop(12 * time.hour, 30 * 24 * time.hour, fn (info acme.CertInfo) {
			// Note: cannot capture logger in callback closure
			println('acme: certificate renewed, restart server to use new cert')
			println('acme: new cert: ${info.cert_path}')
		})
	} else {
		// Start HTTP proxy on public port (no ACME)
		spawn http_proxy.listen()
	}

	tls_enabled := tls_cert.len > 0 && tls_key.len > 0

	// Warn if auth tokens are sent over plaintext
	if auth_enabled && !tls_enabled {
		logger.warn('auth enabled without TLS, tokens sent in plaintext')
	}

	// Start WebSocket listener if configured
	if cfg.ws_port > 0 {
		spawn start_ws_listener(mut registry, tokens, auth_enabled, cfg.ws_port, logger)
	}

	if tls_enabled {
		// TLS mode: accept TLS connections using mbedtls
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
			spawn handle_control(mut tun, mut registry, tokens, auth_enabled, logger)
		}
	} else {
		// Plain TCP mode
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
			spawn handle_control(mut tun, mut registry, tokens, auth_enabled, logger)
		}
	}
}

// handle_control manages a single tunnel client control connection.
// The Tunnel is created before spawning so the Transport is already wrapped.
fn handle_control(mut tun tunnel.Tunnel, mut registry proxy.Registry, tokens []string, auth_enabled bool, logger &slog.Logger) {
	ctrl := logger.with_component('control')
	defer {
		tun.close()
	}

	// Auth handshake (if enabled)
	if auth_enabled {
		f := tun.read_frame() or {
			ctrl.error('failed to read auth frame', err: '${err}')
			return
		}
		if f.msg_type != .auth {
			// Client didn't send auth — reject
			err_frame := protocol.new_frame(0, .err, 'authentication required'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.error('expected auth frame', detail: '${f.msg_type}')
			return
		}
		token := f.payload.bytestr()
		if !auth.validate_token(tokens, token) {
			err_frame := protocol.new_frame(0, .err, 'invalid token'.bytes())
			tun.write_raw(err_frame.encode()) or {}
			ctrl.error('invalid token', token: token)
			return
		}
		// Auth OK — send confirmation
		ok_frame := protocol.new_frame(0, .auth_ok, [])
		tun.write_raw(ok_frame.encode()) or {
			ctrl.error('failed to send auth_ok', err: '${err}')
			return
		}
		ctrl.info('authenticated', token: token)
	}

	// Read the registration frame
	f := tun.read_frame() or {
		ctrl.error('failed to read register frame', err: '${err}')
		return
	}
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

	// Send registration ack so the client knows it succeeded
	reg_ok_frame := protocol.new_frame(0, .reg_ok, subdomain.bytes())
	tun.write_raw(reg_ok_frame.encode()) or {
		ctrl.error('failed to send reg_ok', err: '${err}', subdomain: subdomain)
		return
	}
	ctrl.info('tunnel registered', subdomain: subdomain)

	// Start the write loop, ping loop, and block on read loop
	spawn tun.run_write_loop()
	spawn tun.run_ping_loop()
	// Server read loop: no DataOpen from client direction (server-initiated streams only)
	tun.run_read_loop(fn (stream_id u32, payload []u8) {
	})

	ctrl.info('tunnel disconnected', subdomain: subdomain)
}

// --- WebSocket listener ---

// WsEvent represents an incoming WebSocket event dispatched from callbacks.
struct WsEvent {
	client_id  string
	payload    []u8
	is_close   bool
	client_ptr voidptr // &websocket.Client for first message from a new client
}

// WsDispatchCtx holds the event channel shared by WebSocket callbacks.
@[heap]
struct WsDispatchCtx {
	events chan WsEvent
}

// start_ws_listener creates a WebSocket server and dispatches connections to handle_control.
fn start_ws_listener(mut registry proxy.Registry, tokens []string, auth_enabled bool, port int, logger &slog.Logger) {
	events := chan WsEvent{cap: 256}
	ctx := &WsDispatchCtx{
		events: events
	}

	mut ws_server := websocket.new_server(.ip, port, '/tunnel')

	ws_server.on_message_ref(ws_server_on_message, voidptr(ctx))
	ws_server.on_close_ref(ws_server_on_close, voidptr(ctx))

	// Start dispatch loop that routes messages and creates tunnels
	spawn ws_dispatch_loop(events, mut registry, tokens, auth_enabled, logger)

	logger.info('websocket listener started', detail: ':${port}')
	ws_server.listen() or { logger.error('websocket listener error', err: '${err}') }
}

// ws_server_on_message pushes incoming binary messages to the dispatch channel.
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

// ws_server_on_close pushes a close event to the dispatch channel.
fn ws_server_on_close(mut c websocket.Client, code int, reason string, ptr voidptr) ! {
	ctx := unsafe { &WsDispatchCtx(ptr) }
	ev := WsEvent{
		client_id: c.id
		is_close:  true
	}
	ctx.events.try_push(&ev)
}

// ws_dispatch_loop reads WebSocket events and routes them to per-client tunnels.
// Runs in a single goroutine — no synchronization needed for the routes map.
fn ws_dispatch_loop(events chan WsEvent, mut registry proxy.Registry, tokens []string, auth_enabled bool, logger &slog.Logger) {
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
			// Known client — route message to its transport channel
			if rx := routes[ev.client_id] {
				payload := ev.payload
				rx.try_push(&payload)
			}
			continue
		}

		// New client — create transport and tunnel
		rx := chan []u8{cap: 128}
		routes[ev.client_id] = rx
		first_payload := ev.payload
		rx.try_push(&first_payload) // first message (auth or registration frame)

		ws_client := unsafe { &websocket.Client(ev.client_ptr) }
		mut t := transport.new_ws_server_transport(ws_client, rx)
		mut tun := tunnel.new(t)
		spawn handle_control(mut tun, mut registry, tokens, auth_enabled, logger)
	}
}
