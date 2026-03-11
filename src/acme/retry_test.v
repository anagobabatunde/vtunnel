module acme

import net.http

// --- backoff_ms ---

fn test_backoff_ms_attempt_zero() {
	wait := backoff_ms(0)
	// base = 1000, jitter +/- 250
	assert wait >= 750, 'attempt 0 should be >= 750, got ${wait}'
	assert wait <= 1250, 'attempt 0 should be <= 1250, got ${wait}'
}

fn test_backoff_ms_doubles_each_attempt() {
	for _ in 0 .. 10 {
		w0 := backoff_ms(0)
		w1 := backoff_ms(1)
		w2 := backoff_ms(2)
		// attempt 0: ~1000 +/- 250
		assert w0 >= 750 && w0 <= 1250, 'attempt 0 out of range: ${w0}'
		// attempt 1: ~2000 +/- 500
		assert w1 >= 1500 && w1 <= 2500, 'attempt 1 out of range: ${w1}'
		// attempt 2: ~4000 +/- 1000
		assert w2 >= 3000 && w2 <= 5000, 'attempt 2 out of range: ${w2}'
	}
}

fn test_backoff_ms_capped_at_max() {
	wait := backoff_ms(20)
	// max = 8000, jitter +/- 2000
	assert wait >= 6000, 'capped backoff should be >= 6000, got ${wait}'
	assert wait <= 10000, 'capped backoff should be <= 10000, got ${wait}'
}

// --- is_retryable_status ---

fn test_is_retryable_status_429() {
	assert is_retryable_status(429) == true
}

fn test_is_retryable_status_500() {
	assert is_retryable_status(500) == true
}

fn test_is_retryable_status_503() {
	assert is_retryable_status(503) == true
}

fn test_is_retryable_status_200() {
	assert is_retryable_status(200) == false
}

fn test_is_retryable_status_201() {
	assert is_retryable_status(201) == false
}

fn test_is_retryable_status_400() {
	assert is_retryable_status(400) == false
}

fn test_is_retryable_status_404() {
	assert is_retryable_status(404) == false
}

// --- is_bad_nonce ---

fn test_is_bad_nonce_detects_bad_nonce() {
	resp := http.Response{
		status_code: 400
		body:        '{"type":"urn:ietf:params:acme:error:badNonce","detail":"JWS has invalid nonce"}'
	}
	assert is_bad_nonce(resp) == true
}

fn test_is_bad_nonce_wrong_status() {
	resp := http.Response{
		status_code: 200
		body:        '{"type":"urn:ietf:params:acme:error:badNonce"}'
	}
	assert is_bad_nonce(resp) == false
}

fn test_is_bad_nonce_different_error() {
	resp := http.Response{
		status_code: 400
		body:        '{"type":"urn:ietf:params:acme:error:malformed"}'
	}
	assert is_bad_nonce(resp) == false
}

fn test_is_bad_nonce_empty_body() {
	resp := http.Response{
		status_code: 400
		body:        ''
	}
	assert is_bad_nonce(resp) == false
}

fn test_is_bad_nonce_500_with_nonce_text() {
	resp := http.Response{
		status_code: 500
		body:        'badNonce'
	}
	assert is_bad_nonce(resp) == false, '500 should not be treated as badNonce'
}

// --- parse_retry_after ---

fn test_parse_retry_after_valid_seconds() {
	assert parse_retry_after('30') == 30000
}

fn test_parse_retry_after_one_second() {
	assert parse_retry_after('1') == 1000
}

fn test_parse_retry_after_zero_fallback() {
	assert parse_retry_after('0') == initial_backoff_ms
}

fn test_parse_retry_after_negative_fallback() {
	assert parse_retry_after('-5') == initial_backoff_ms
}

fn test_parse_retry_after_non_numeric_fallback() {
	assert parse_retry_after('Thu, 01 Jan 2026 00:00:00 GMT') == initial_backoff_ms
}

fn test_parse_retry_after_empty_fallback() {
	assert parse_retry_after('') == initial_backoff_ms
}

fn test_parse_retry_after_with_whitespace() {
	assert parse_retry_after('  60  ') == 60000
}

// --- retry_wait_ms ---

fn test_retry_wait_ms_falls_back_to_backoff_for_500() {
	resp := http.Response{
		status_code: 500
		body:        'internal server error'
	}
	wait := retry_wait_ms(resp, 0)
	// Should use backoff_ms(0) which is ~1000 +/- 250
	assert wait >= 750 && wait <= 1250, 'expected ~1000ms for 500, got ${wait}'
}

fn test_retry_wait_ms_falls_back_to_backoff_for_200() {
	resp := http.Response{
		status_code: 200
		body:        'ok'
	}
	wait := retry_wait_ms(resp, 1)
	// Should use backoff_ms(1) which is ~2000 +/- 500
	assert wait >= 1500 && wait <= 2500, 'expected ~2000ms for 200, got ${wait}'
}

// --- renewal_backoff ---

fn test_renewal_backoff_first_failure() {
	assert renewal_backoff(1) == 60
}

fn test_renewal_backoff_second_failure() {
	assert renewal_backoff(2) == 120
}

fn test_renewal_backoff_third_failure() {
	assert renewal_backoff(3) == 240
}

fn test_renewal_backoff_capped() {
	// 60 * 2^6 = 3840 > 3600, so failures >= 7 should be capped
	assert renewal_backoff(7) == 3600
}

fn test_renewal_backoff_large_value_stays_capped() {
	assert renewal_backoff(20) == 3600
}

fn test_renewal_backoff_zero_returns_initial() {
	assert renewal_backoff(0) == 60
}
