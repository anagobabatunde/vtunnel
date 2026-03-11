module auth

import os

// --- generate_token ---

fn test_generate_token_length() {
	token := generate_token()!
	assert token.len == 32, 'token should be 32 hex chars (16 bytes)'
}

fn test_generate_token_is_hex() {
	token := generate_token()!
	for c in token {
		is_hex := (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`)
		assert is_hex, 'token should only contain hex chars, got: ${c}'
	}
}

fn test_generate_token_uniqueness() {
	t1 := generate_token()!
	t2 := generate_token()!
	assert t1 != t2, 'consecutive tokens should be unique'
}

// --- validate_token ---

fn test_validate_token_valid() {
	tokens := ['abc123', 'def456', 'ghi789']
	assert validate_token(tokens, 'def456') == true
}

fn test_validate_token_invalid() {
	tokens := ['abc123', 'def456']
	assert validate_token(tokens, 'wrong') == false
}

fn test_validate_token_empty_list() {
	tokens := []string{}
	assert validate_token(tokens, 'any') == false
}

fn test_validate_token_empty_string() {
	tokens := ['abc123']
	assert validate_token(tokens, '') == false
}

fn test_validate_token_exact_match_required() {
	tokens := ['abc123']
	assert validate_token(tokens, 'abc12') == false
	assert validate_token(tokens, 'abc1234') == false
	assert validate_token(tokens, 'ABC123') == false
}

// --- constant_time_eq ---

fn test_constant_time_eq_equal() {
	assert constant_time_eq('hello', 'hello') == true
}

fn test_constant_time_eq_different() {
	assert constant_time_eq('hello', 'world') == false
}

fn test_constant_time_eq_different_lengths() {
	assert constant_time_eq('short', 'longer') == false
}

fn test_constant_time_eq_empty() {
	assert constant_time_eq('', '') == true
}

// --- redact_token ---

fn test_redact_token_normal() {
	result := redact_token('abcdefghijklmnop')
	assert result == 'abcd...mnop'
}

fn test_redact_token_exactly_32_chars() {
	token := 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6'
	result := redact_token(token)
	assert result == 'a1b2...c5d6'
}

fn test_redact_token_short() {
	assert redact_token('abcd') == '****'
	assert redact_token('12345678') == '****'
}

fn test_redact_token_empty() {
	assert redact_token('') == '****'
}

fn test_redact_token_9_chars() {
	result := redact_token('123456789')
	assert result == '1234...6789'
}

// --- save_token / load_tokens ---

fn test_save_and_load_tokens() {
	path := '/tmp/vtunnel_test_tokens_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}

	save_token(path, 'token_one')!
	save_token(path, 'token_two')!

	tokens := load_tokens(path)!
	assert tokens.len == 2
	assert tokens[0] == 'token_one'
	assert tokens[1] == 'token_two'
}

fn test_load_tokens_ignores_empty_lines() {
	path := '/tmp/vtunnel_test_empty_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'token1\n\n\ntoken2\n')!

	tokens := load_tokens(path)!
	assert tokens.len == 2
}

fn test_load_tokens_ignores_comments() {
	path := '/tmp/vtunnel_test_comments_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, '# this is a comment\ntoken1\n# another comment\ntoken2\n')!

	tokens := load_tokens(path)!
	assert tokens.len == 2
	assert tokens[0] == 'token1'
	assert tokens[1] == 'token2'
}

fn test_load_tokens_trims_whitespace() {
	path := '/tmp/vtunnel_test_trim_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, '  token1  \n\ttoken2\t\n')!

	tokens := load_tokens(path)!
	assert tokens[0] == 'token1'
	assert tokens[1] == 'token2'
}

fn test_load_tokens_nonexistent_file_returns_error() {
	if _ := load_tokens('/tmp/does_not_exist_ever_12345.txt') {
		assert false, 'should return error for missing file'
	}
}

// --- validate_subdomain ---

fn test_validate_subdomain_valid() {
	validate_subdomain('myapp') or { assert false, 'myapp should be valid' }
	validate_subdomain('my-app') or { assert false, 'my-app should be valid' }
	validate_subdomain('app123') or { assert false, 'app123 should be valid' }
	validate_subdomain('a') or { assert false, 'single char should be valid' }
	validate_subdomain('a-b-c') or { assert false, 'multi-hyphen should be valid' }
}

fn test_validate_subdomain_empty() {
	if _ := validate_subdomain('') {
		assert false, 'empty subdomain should fail'
	}
}

fn test_validate_subdomain_too_long() {
	long := 'a'.repeat(64)
	if _ := validate_subdomain(long) {
		assert false, '64 char subdomain should fail'
	}
	// 63 chars should pass
	ok := 'a'.repeat(63)
	validate_subdomain(ok) or { assert false, '63 chars should be valid' }
}

fn test_validate_subdomain_leading_hyphen() {
	if _ := validate_subdomain('-myapp') {
		assert false, 'leading hyphen should fail'
	}
}

fn test_validate_subdomain_trailing_hyphen() {
	if _ := validate_subdomain('myapp-') {
		assert false, 'trailing hyphen should fail'
	}
}

fn test_validate_subdomain_uppercase() {
	if _ := validate_subdomain('MyApp') {
		assert false, 'uppercase should fail'
	}
}

fn test_validate_subdomain_special_chars() {
	if _ := validate_subdomain('my_app') {
		assert false, 'underscore should fail'
	}
	if _ := validate_subdomain('my.app') {
		assert false, 'dot should fail'
	}
	if _ := validate_subdomain('my app') {
		assert false, 'space should fail'
	}
}

fn test_validate_subdomain_max_length_boundary() {
	// Exactly 63 chars — should pass
	validate_subdomain('a'.repeat(63)) or { assert false, '63 chars should be valid' }
	// Exactly 1 char — should pass
	validate_subdomain('a') or { assert false, '1 char should be valid' }
}

fn test_save_token_creates_file() {
	path := '/tmp/vtunnel_test_create_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	assert !os.exists(path)
	save_token(path, 'newtoken')!
	assert os.exists(path)
	tokens := load_tokens(path)!
	assert tokens[0] == 'newtoken'
}
