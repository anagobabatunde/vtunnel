# V Language Rules

## Error Handling
- Always use `fn foo() ! { }` or `fn foo() !Type { }` for fallible functions.
- Handle errors with `or { return err }` or `or { panic(err) }` (only in main/tests).
- Never silently ignore errors — at minimum log them.

## Memory & Performance
- V is garbage-collected by default. Don't fight it.
- Use `[]u8` buffers and `io.read()` for streaming — avoid loading large payloads into memory.
- Prefer `strings.Builder` for string concatenation in loops.
- Use `@[heap]` attribute on structs that need heap allocation.

## Concurrency
- Use `spawn fn_name()` to launch coroutines.
- Use `chan T` for typed channels between coroutines.
- Always close channels when done sending.
- Use `select {}` for multiplexing channel reads.
- Shared data must use `shared` keyword or be communicated via channels.

## Networking
- Use `net.TcpListener` and `net.TcpConn` for raw TCP.
- Use `net.websocket.Client` / `net.websocket.Server` for WebSocket.
- Always set timeouts on socket operations.
- Close connections in `defer {}` blocks.

## Testing
- Test files live alongside source: `foo.v` → `foo_test.v`.
- Test function names: `fn test_descriptive_name() { }`.
- Use `assert` for assertions.
- Integration tests go in `tests/` directory.

## Module Organization
- One module per directory.
- `module name` must match directory name.
- Keep module interfaces small — only export what's needed.
- Use `pub` sparingly.
