# VTunnel

Open-source ngrok alternative — expose local services to the internet. Written in [V](https://vlang.io).

[![CI](https://github.com/user/vtunnel/actions/workflows/ci.yml/badge.svg)](https://github.com/user/vtunnel/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Features

- **Multiplexed streams** over a single control connection (binary framing protocol)
- **TCP, TLS, and WebSocket** transport support
- **ACME/Let's Encrypt** auto-TLS with HTTP-01 challenges and auto-renewal
- **Token-based authentication** with constant-time validation
- **Subdomain-based routing** via Host header extraction
- **Structured logging** (human-readable with colors, or JSON)
- **Auto-reconnection** with exponential backoff and jitter
- **Graceful shutdown** (SIGINT/SIGTERM)
- **Single binary**, zero external dependencies

## Quick Start

**Prerequisites:** [V](https://vlang.io) 0.4.x

```bash
# Build
v -prod cmd/server/ -o vtunnel-server
v -prod cmd/client/ -o vtunnel-client

# Generate an auth token
./vtunnel-server --generate-token --token-file tokens.txt

# Start the relay server
./vtunnel-server --port 8080 --http-port 80 --domain example.com --token-file tokens.txt

# On your local machine, expose port 3000
./vtunnel-client --server example.com:8080 --local localhost:3000 --subdomain myapp --token <your-token>

# Visit http://myapp.example.com to reach your local service
```

## Architecture

```
Internet Client ──> Public Server (:443/:80) ──> Relay (mux) ──> Control Conn ──> Local Client ──> Local Service
```

1. **Client** opens a persistent control connection (TCP, TLS, or WebSocket) to the **Server**.
2. Server assigns a public subdomain and registers the tunnel.
3. When an external request arrives, the server multiplexes it over the control connection using stream IDs.
4. Client demuxes, forwards to the local service, and streams the response back.

All traffic is multiplexed over a single connection using a binary framing protocol: `[stream_id: u32][msg_type: u8][length: u32][payload]`.

## Server CLI

```
vtunnel-server [options]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `8080` | Control port for tunnel clients |
| `--http-port` | `80` | Public HTTP port for visitors |
| `--host` | `0.0.0.0` | Bind address |
| `--domain` | `localhost` | Base domain for subdomains |
| `--token-file` | | Path to token file (enables auth) |
| `--generate-token` | | Generate a new token and exit |
| `--tls-cert` | | TLS certificate PEM file |
| `--tls-key` | | TLS private key PEM file |
| `--ws-port` | `0` (disabled) | WebSocket listener port |
| `--acme` | | Enable ACME auto-TLS via Let's Encrypt |
| `--acme-email` | | Contact email for ACME account |
| `--acme-dir` | `~/.vtunnel/certs` | Cert storage directory |
| `--acme-staging` | | Use Let's Encrypt staging environment |
| `--log-level` | `info` | `debug`, `info`, `warn`, `error` |
| `--log-format` | `human` | `human`, `json` |

## Client CLI

```
vtunnel-client [options]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--server` | `localhost:8080` | Server address (host:port) |
| `--local` | `localhost:3000` | Local service address |
| `--subdomain` | `myapp` | Subdomain to register |
| `--token` | | Auth token for server |
| `--tls` | | Connect using TLS |
| `--tls-ca` | | CA certificate PEM for server verification |
| `--ws` | | Connect via WebSocket instead of TCP |
| `--log-level` | `info` | `debug`, `info`, `warn`, `error` |
| `--log-format` | `human` | `human`, `json` |

## TLS

Three modes are supported:

**Manual TLS** — bring your own certificates:
```bash
./vtunnel-server --tls-cert cert.pem --tls-key key.pem --port 443 --domain example.com
./vtunnel-client --server example.com:443 --tls --local localhost:3000
```

**ACME auto-TLS** — automatic Let's Encrypt certificates:
```bash
./vtunnel-server --acme --acme-email you@example.com --domain example.com --port 443 --http-port 80
```

**No TLS** — for development only:
```bash
./vtunnel-server --port 8080 --http-port 80
./vtunnel-client --server localhost:8080 --local localhost:3000
```

## Development

```bash
# Build
v cmd/server/         # Build server
v cmd/client/         # Build client

# Test
v test src/           # Run all unit tests

# Format & lint
v fmt -w .            # Format all V files
v vet .               # Static analysis
```

## Project Structure

```
vtunnel/
├── cmd/
│   ├── server/           # Relay server entry point
│   │   └── main.v
│   └── client/           # Client CLI entry point
│       └── main.v
├── src/
│   ├── acme/             # ACME/Let's Encrypt auto-TLS
│   ├── auth/             # Token-based auth & validation
│   ├── config/           # CLI flags & config parsing
│   ├── protocol/         # Wire protocol (framing, serialization)
│   ├── proxy/            # HTTP proxy & tunnel registry
│   ├── slog/             # Structured logging
│   ├── transport/        # TCP, TLS, WebSocket transports
│   └── tunnel/           # Stream multiplexing
├── v.mod                 # V module manifest
├── LICENSE               # MIT
└── CLAUDE.md             # Claude Code context
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
