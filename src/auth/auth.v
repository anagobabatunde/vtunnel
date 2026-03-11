module auth

import crypto.rand
import encoding.hex
import os

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
