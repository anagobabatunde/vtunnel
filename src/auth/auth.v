module auth

import crypto.rand
import encoding.hex
import os

// AuthResult holds the result of authenticating a token/API key.
// Contains user identity and tier-based limits for the session.
pub struct AuthResult {
pub:
	user_id      string // user identifier (or "self-hosted" in standalone mode)
	tier         string // "free", "pro", or "self-hosted"
	max_tunnels  int    // max concurrent tunnels (-1 = unlimited)
	max_bw_bytes i64    // max bandwidth per month in bytes (-1 = unlimited)
}

// Authenticator validates a token/API key and returns auth context.
// Implemented by FileAuthenticator (standalone) and DbAuthenticator (hosted).
pub interface Authenticator {
	// requires_auth returns true if clients must send an auth frame.
	requires_auth() bool
	// validate checks a token and returns auth context on success.
	validate(token string) !AuthResult
}

// FileAuthenticator validates tokens against a file-based whitelist.
// Used in standalone/self-hosted mode. Returns unlimited AuthResult on success.
@[heap]
pub struct FileAuthenticator {
	tokens []string
}

// new_file_authenticator creates an authenticator using a list of tokens.
pub fn new_file_authenticator(tokens []string) &FileAuthenticator {
	return &FileAuthenticator{
		tokens: tokens
	}
}

// requires_auth returns true because file-based auth requires a token.
pub fn (a &FileAuthenticator) requires_auth() bool {
	return true
}

// validate checks the token against the whitelist and returns an unlimited AuthResult.
pub fn (a &FileAuthenticator) validate(token string) !AuthResult {
	if !validate_token(a.tokens, token) {
		return error('invalid token')
	}
	return AuthResult{
		user_id:      'self-hosted'
		tier:         'self-hosted'
		max_tunnels:  -1
		max_bw_bytes: -1
	}
}

// NoAuthenticator accepts any connection without authentication.
// Used when no --token-file is set (dev mode).
@[heap]
pub struct NoAuthenticator {}

// new_no_authenticator creates an authenticator that accepts everything.
pub fn new_no_authenticator() &NoAuthenticator {
	return &NoAuthenticator{}
}

// requires_auth returns false because no-auth mode accepts everything.
pub fn (a &NoAuthenticator) requires_auth() bool {
	return false
}

// validate always succeeds with unlimited permissions.
pub fn (a &NoAuthenticator) validate(token string) !AuthResult {
	return AuthResult{
		user_id:      'anonymous'
		tier:         'self-hosted'
		max_tunnels:  -1
		max_bw_bytes: -1
	}
}

// generate_random_subdomain creates a random subdomain for free-tier users.
// Format: adjective-noun-4hex, e.g., "swift-tunnel-a3f2".
pub fn generate_random_subdomain() !string {
	adjectives := ['swift', 'calm', 'bold', 'keen', 'warm', 'cool', 'fast', 'neat', 'wise', 'true',
		'fair', 'deep', 'pure', 'safe', 'glad']
	nouns := ['tunnel', 'bridge', 'link', 'path', 'gate', 'port', 'node', 'beam', 'core', 'wave',
		'pipe', 'lane', 'mesh', 'flow', 'wire']
	suffix_bytes := rand.read(2)!
	suffix := hex.encode(suffix_bytes)
	adj_idx := suffix_bytes[0] % u8(adjectives.len)
	noun_idx := suffix_bytes[1] % u8(nouns.len)
	return '${adjectives[adj_idx]}-${nouns[noun_idx]}-${suffix}'
}

// generate_token creates a cryptographically random 32-character hex token.
pub fn generate_token() !string {
	bytes := rand.read(16)!
	return hex.encode(bytes)
}

// load_tokens reads tokens from a file, one per line.
// Ignores empty lines and lines starting with #.
pub fn load_tokens(path string) ![]string {
	content := os.read_file(path)!
	mut tokens := []string{}
	for line in content.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.len > 0 && !trimmed.starts_with('#') {
			tokens << trimmed
		}
	}
	return tokens
}

// save_token appends a token to the given file, creating it if needed.
pub fn save_token(path string, token string) ! {
	mut f := os.open_append(path) or { os.create(path)! }
	defer {
		f.close()
	}
	f.write_string('${token}\n')!
}

// validate_token checks whether a token is in the allowed list.
// Uses constant-time comparison to prevent timing side-channel attacks.
pub fn validate_token(tokens []string, token string) bool {
	for t in tokens {
		if constant_time_eq(t, token) {
			return true
		}
	}
	return false
}

// constant_time_eq compares two strings in constant time to prevent timing attacks.
// Always compares all bytes regardless of where mismatches occur.
fn constant_time_eq(a string, b string) bool {
	if a.len != b.len {
		return false
	}
	mut result := u8(0)
	for i in 0 .. a.len {
		result |= a[i] ^ b[i]
	}
	return result == 0
}

// redact_token returns a redacted version for safe logging.
// Shows first 4 and last 4 characters: "abcd...wxyz".
pub fn redact_token(token string) string {
	if token.len <= 8 {
		return '****'
	}
	return '${token[..4]}...${token[token.len - 4..]}'
}

// validate_subdomain checks that a subdomain is well-formed.
// Rules: 1-63 chars, lowercase alphanumeric and hyphens only,
// must not start or end with a hyphen.
pub fn validate_subdomain(name string) ! {
	if name == '' {
		return error('subdomain must not be empty')
	}
	if name.len > 63 {
		return error('subdomain too long: ${name.len} chars (max 63)')
	}
	if name[0] == `-` || name[name.len - 1] == `-` {
		return error('subdomain must not start or end with a hyphen')
	}
	for i, c in name {
		is_lower := c >= `a` && c <= `z`
		is_digit := c >= `0` && c <= `9`
		is_hyphen := c == `-`
		if !(is_lower || is_digit || is_hyphen) {
			return error('subdomain contains invalid character at position ${i}: ${[
				u8(c),
			].bytestr()}')
		}
	}
}
