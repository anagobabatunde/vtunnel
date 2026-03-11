# Architecture Rules

## Tunnel Design
- The control connection is the single persistent link between client and server.
- All tunnel traffic is multiplexed over this connection using stream IDs.
- Each proxied request gets a unique stream ID (u32).
- The server never initiates connections to the client's network.

## Protocol
- Use a binary framing protocol: `[stream_id: u32][msg_type: u8][length: u32][payload]`.
- Message types: `DataOpen`, `Data`, `DataClose`, `Ping`, `Pong`, `Auth`, `AuthOK`, `Error`.
- All multi-byte integers are big-endian (network byte order).

## Security
- Auth tokens are generated server-side and validated on every control connection.
- No secrets in logs — redact tokens, only show first/last 4 chars.
- TLS should be optional but strongly encouraged for production.
- Rate-limit new tunnel registrations per IP.

## Separation of Concerns
- `transport/` handles raw byte I/O (TCP, WebSocket).
- `protocol/` handles framing, serialization, deserialization.
- `tunnel/` handles stream multiplexing logic.
- `proxy/` handles HTTP-level request routing on the server.
- `auth/` handles handshake and token validation.
- `cmd/` is thin — just CLI parsing and wiring modules together.
