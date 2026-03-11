# VTunnel — Open-Source ngrok Alternative in V

A self-hosted tunneling tool that exposes local services to the internet via a relay server. Written in V for speed, simplicity, and single-binary deployment.

## Tech Stack

- **Language**: V (vlang) 0.4.x
- **Networking**: V stdlib `net`, `net.http`, `net.websocket`, `io`, `crypto`
- **Build**: `v .` (zero dependencies)
- **Tests**: `v test .` (V built-in test runner)

## Project Structure

```
vtunnel/
├── CLAUDE.md              # This file — Claude Code context
├── v.mod                  # V module manifest
├── cmd/
│   ├── server/            # Relay server entry point
│   │   └── main.v
│   └── client/            # Client CLI entry point
│       └── main.v
├── src/
│   ├── acme/              # ACME/Let's Encrypt auto-TLS
│   ├── auth/              # Token-based auth & handshake
│   ├── config/            # CLI flags & config parsing
│   ├── protocol/          # Wire protocol (message types, serialization)
│   ├── proxy/             # HTTP/TCP proxy handlers on server side
│   ├── slog/              # Structured logging
│   ├── transport/         # TCP/TLS/WebSocket transport layer
│   └── tunnel/            # Core tunnel logic (mux, demux, framing)
└── .claude/               # Claude Code configuration
    ├── rules/             # Coding rules
    └── commands/          # Slash commands
```

## Architecture Overview

```
Internet Client → [Public Server :443/:80] → Relay (mux) → [Control Conn] → Local Client → Local Service
```

1. **Client** opens a persistent control connection (WebSocket or raw TCP) to the **Server**.
2. Server assigns a public subdomain/port and registers the tunnel.
3. When an external request hits the server, it multiplexes it over the control connection.
4. Client demuxes, forwards to the local service, and streams the response back.

Key architectural decisions:
- Multiplexed streams over a single control connection (avoid per-request connections).
- Binary framing protocol for efficiency — length-prefixed messages.
- Server is stateless per-tunnel; all state lives in the connection.

## Common Commands

```bash
# Build
v cmd/server/            # Build server binary
v cmd/client/            # Build client binary

# Run
./server --port 8080     # Start relay server
./client --server example.com --local 3000   # Expose local port 3000

# Test
v test .                 # Run all tests
v test src/tunnel/       # Test specific module
v test tests/            # Integration tests

# Format & lint
v fmt -w .               # Format all V files in place
v vet .                  # Static analysis
```

## Code Standards

- Use V's built-in error handling (`!` and `or {}` blocks) — never panic in library code.
- All public functions must have doc comments (`//` above the function).
- Module names are lowercase single words matching the directory.
- Use `snake_case` for functions/variables, `PascalCase` for types/structs.
- Prefer `[]u8` for byte buffers, not strings, when handling binary data.
- Keep functions short (< 50 lines). Extract helpers.
- No global mutable state — pass config/state via structs.
- Use V's `spawn` for concurrency, channels for communication.
- Error messages should be lowercase, no trailing punctuation.

## V-Specific Patterns

- Use `struct` embedding for composition over inheritance.
- Use `interface` for transport/protocol abstractions.
- Use `enum` for message types and state machines.
- Use `@[params]` attribute for optional function parameters.
- Prefer `defer { ... }` for cleanup (closing sockets, etc.).
- Use `arrays.parallel_map` or manual `spawn` for parallelism.

## Git Conventions

- Commit messages: `type: short description` (e.g., `feat: add TLS support`)
- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
- One logical change per commit.

## Important Warnings

- V's `net.websocket` API may differ between versions — always check V docs.
- V compiles to C — be mindful of C interop edge cases with raw pointers.
- Avoid `unsafe {}` blocks unless absolutely necessary (e.g., low-level socket ops).
- Test on both macOS and Linux — socket behavior can differ.
