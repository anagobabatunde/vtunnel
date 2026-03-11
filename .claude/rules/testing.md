# Testing Rules

## Test File Placement
- Unit tests live alongside source: `foo.v` → `foo_test.v` in the same module.
- Integration tests go in `tests/` directory.
- Test files must declare the same `module` as the source they test.

## Test Naming
- Function names: `fn test_<function>_<scenario>() { }`.
- Be descriptive: `test_validate_token_empty_list`, not `test_validate_2`.
- Group tests by the function they exercise using comments: `// --- function_name ---`.

## Test Structure
- Arrange-Act-Assert pattern. Keep tests short (< 20 lines).
- One assertion per logical behavior. Multiple asserts are OK if testing one concept.
- Use `assert condition, 'message'` for clarity on failure.
- Test both happy path AND error/edge cases for every public function.

## What to Test
- Every `pub fn` must have at least one test.
- Test error returns with `if _ := fallible_fn() { assert false, 'should error' }`.
- Test boundary values: empty inputs, max values, zero, nil/none.
- Test roundtrips: encode → decode, save → load.
- For concurrent code: test channel push/pop, test close behavior.

## What NOT to Test
- Private functions — test them through public API.
- `main()` functions — use integration tests instead.
- Simple struct constructors with no logic.

## Running Tests
- `v test src/` — run all unit tests.
- `v test src/protocol/` — run a specific module.
- `v test tests/` — run integration tests.
- Always run `v test src/` before committing.

## Test Isolation
- Tests must not depend on each other or run order.
- Clean up temp files with `defer { os.rm(path) or {} }`.
- Use `os.getpid()` in temp file paths to avoid collisions.
- Never bind to fixed ports in unit tests — use integration tests for networking.

## Security Testing
- Auth: test valid, invalid, empty, and near-miss tokens.
- Protocol: test oversized payloads, truncated frames, malformed headers.
- Never log real tokens in test output — use redact_token.
