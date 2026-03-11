# Contributing to VTunnel

## Prerequisites

- [V](https://vlang.io) 0.4.x
- Git

## Getting Started

```bash
git clone https://github.com/user/vtunnel.git
cd vtunnel
v cmd/server/          # Build server
v cmd/client/          # Build client
v test src/            # Run tests
```

## Code Style

- Run `v fmt -w .` before committing
- Run `v vet .` for static analysis
- `snake_case` for functions and variables
- `PascalCase` for types and structs
- Doc comments (`//`) on all `pub` functions
- Keep functions under 50 lines
- Use `[]u8` for byte buffers, not strings
- Handle errors with `!` and `or {}` — never panic in library code

## Testing

- Every `pub fn` must have at least one test
- Test files live alongside source: `foo.v` -> `foo_test.v`
- Name tests descriptively: `fn test_validate_token_empty_list()`
- Test both happy path and error cases
- Run all tests: `v test src/`

## Commit Messages

Format: `type: short description`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Examples:
- `feat: add WebSocket transport support`
- `fix: handle empty token file gracefully`
- `test: add boundary tests for frame parsing`

## Pull Requests

- One logical change per PR
- All tests must pass
- Code must be formatted (`v fmt`) and pass `v vet`
- Include a description of what and why

## Reporting Issues

Include:
- V version (`v version`)
- Operating system
- Steps to reproduce
- Expected vs actual behavior
