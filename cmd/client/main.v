module main

import net
import os
import rand
import time
import src.config
import src.slog
import src.tunnel
import src.protocol
import src.transport

fn main() {
	cfg := config.parse_client_args()

	// Create logger from config
	logger := slog.new('client', slog.parse_level(cfg.log_level), slog.parse_format(cfg.log_format))

	// Install signal handlers for graceful shutdown
	// Note: signal handlers cannot capture logger (V closure limitation)
	os.signal_opt(.int, fn (_ os.Signal) {
		println('\nvtunnel-client: shutting down (SIGINT)...')
		exit(0)
	}) or {}
	os.signal_opt(.term, fn (_ os.Signal) {
		println('vtunnel-client: shutting down (SIGTERM)...')
		exit(0)
	}) or {}

	mut backoff_ms := i64(1000)
	max_backoff_ms := i64(30000)

	for {
		start_unix := time.now().unix()

		connect_and_run(cfg, logger) or {
			msg := err.msg()
			logger.error(msg)
			// Auth and registration failures are not retryable — exit immediately
			if msg.starts_with('auth failed') || msg.starts_with('registration failed') {
				return
			}
		}

		// Reset backoff if we were connected for a while (> 60s)
		elapsed := time.now().unix() - start_unix
		if elapsed > 60 {
			backoff_ms = 1000
		}

		// Calculate wait time with jitter (+/- 25%)
		jitter_range := backoff_ms / 4
		jitter := if jitter_range > 0 {
			rand.i64_in_range(-jitter_range, jitter_range + 1) or { 0 }
		} else {
			i64(0)
		}
		wait_ms := backoff_ms + jitter

		logger.info('reconnecting in ${wait_ms}ms')
		time.sleep(wait_ms * time.millisecond)

		// Exponential backoff (cap at max)
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

	// Create transport and tunnel
	mut tun := create_tunnel(cfg, logger)!

	// Auth handshake (if token provided)
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

	// Send registration frame
	reg := protocol.new_frame(0, .data_open, cfg.subdomain.bytes())
	tun.write_raw(reg.encode()) or {
		tun.close()
		return error('failed to send register frame: ${err}')
	}

	// Wait for registration ack
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

	logger.info('connected to ${cfg.server_addr}')
	logger.info('forwarding ${cfg.subdomain} -> ${cfg.local_addr}')

	spawn tun.run_write_loop()
	spawn tun.run_ping_loop()

	// Block on read loop; register streams synchronously, then spawn handler
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
		// WebSocket transport
		ws_mode := if cfg.tls { ' (wss)' } else { '' }
		logger.info('connecting via WebSocket${ws_mode}')
		t := transport.new_ws_client(cfg.server_addr, cfg.tls)!
		return tunnel.new(t)
	}

	if cfg.tls {
		// Parse host:port for TLS dialer
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
	transport.set_nodelay(mut conn)
	transport.tune_socket(mut conn)
	mut tcp := transport.new_tcp(conn)
	tcp.set_read_timeout(tunnel.idle_timeout)
	return tunnel.new(tcp)
}

// handle_stream connects to the local service and relays data for one stream.
// Cleanup is done in correct order to prevent goroutine leaks.
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

	transport.set_nodelay(mut local)

	// Bidirectional relay using shared helpers
	spawn tunnel.pipe_conn_to_stream(mut local, mut tun, s)
	tunnel.pipe_stream_to_conn(mut local, s)

	// Cleanup in correct order:
	// 1. Remove stream — closes s.rx, stops data flow
	// 2. Close local conn — stops pipe_conn_to_stream's read
	// 3. Notify server — send data_close
	tun.remove_stream(s.id)
	local.close() or {}
	tun.send(protocol.new_frame(s.id, .data_close, []))
}
