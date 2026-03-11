Run the unit test suite across all modules

```bash
v test src/
```

If tests fail, analyze the failures and suggest fixes.

To test a specific module, use: `v test src/<module>/` (e.g., `v test src/protocol/`).

For integration tests: `v test tests/`.

After all tests pass, run `v vet .` to check for lint issues.
