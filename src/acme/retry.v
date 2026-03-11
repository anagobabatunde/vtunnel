module acme

import net.http
import rand
import time

// Retry constants for ACME HTTP operations.
const max_retry_attempts = 3
const initial_backoff_ms = i64(1000)
const max_backoff_ms = i64(8000)

// Renewal loop backoff constants.
const renewal_initial_secs = i64(60)
const renewal_max_secs = i64(3600)

// Max transient failures tolerated in polling loops before aborting.
const max_poll_transient = 3

// backoff_ms computes the exponential backoff wait in milliseconds for the given attempt.
// Uses the same pattern as cmd/client/main.v: doubles each attempt, capped, with +/- 25% jitter.
fn backoff_ms(attempt int) i64 {
	mut base := initial_backoff_ms
	for _ in 0 .. attempt {
		base = if base * 2 > max_backoff_ms { max_backoff_ms } else { base * 2 }
	}
	jitter_range := base / 4
	jitter := if jitter_range > 0 {
		rand.i64_in_range(-jitter_range, jitter_range + 1) or { i64(0) }
	} else {
		i64(0)
	}
	return base + jitter
}

// is_retryable_status returns true for HTTP 429 (rate limited) and 5xx (server errors).
fn is_retryable_status(code int) bool {
	return code == 429 || code >= 500
}

// is_bad_nonce returns true if the ACME server returned a badNonce error.
// Per RFC 8555 §6.5, the server returns HTTP 400 with "badNonce" in the response body.
fn is_bad_nonce(resp http.Response) bool {
	return resp.status_code == 400 && resp.body.contains('badNonce')
}

// parse_retry_after parses a Retry-After header value (integer seconds) and returns milliseconds.
// Falls back to initial_backoff_ms if the value is not a positive integer.
fn parse_retry_after(header_val string) i64 {
	secs := header_val.trim_space().i64()
	if secs > 0 {
		return secs * 1000
	}
	return initial_backoff_ms
}

// retry_wait_ms computes the wait time before retrying, respecting Retry-After for 429 responses.
fn retry_wait_ms(resp http.Response, attempt int) i64 {
	if resp.status_code == 429 {
		retry_after := resp.header.get_custom('Retry-After') or { '' }
		if retry_after.len > 0 {
			return parse_retry_after(retry_after)
		}
	}
	return backoff_ms(attempt)
}

// renewal_backoff returns the number of seconds to wait after N consecutive renewal failures.
// Starts at renewal_initial_secs and doubles each failure, capped at renewal_max_secs.
fn renewal_backoff(failures int) i64 {
	if failures <= 0 {
		return renewal_initial_secs
	}
	mut secs := renewal_initial_secs
	for _ in 1 .. failures {
		secs = if secs * 2 > renewal_max_secs { renewal_max_secs } else { secs * 2 }
	}
	return secs
}

// http_get_with_retry performs an HTTP GET with exponential backoff on transient failures.
fn http_get_with_retry(url string) !http.Response {
	mut last_err := ''
	for attempt in 0 .. max_retry_attempts {
		resp := http.get(url) or {
			last_err = '${err}'
			if attempt + 1 < max_retry_attempts {
				time.sleep(backoff_ms(attempt) * time.millisecond)
			}
			continue
		}
		if is_retryable_status(resp.status_code) && attempt + 1 < max_retry_attempts {
			last_err = 'HTTP ${resp.status_code}'
			time.sleep(retry_wait_ms(resp, attempt) * time.millisecond)
			continue
		}
		return resp
	}
	return error('${last_err} (after ${max_retry_attempts} attempts)')
}

// signed_post performs a JWS-signed ACME POST with automatic nonce refresh and retry.
// Each retry fetches a fresh nonce and re-signs the request. badNonce errors trigger
// an immediate retry without backoff. Network errors and 5xx/429 use exponential backoff.
fn (c &AcmeClient) signed_post(url string, payload string) !http.Response {
	mut last_err := ''
	for attempt in 0 .. max_retry_attempts {
		nonce := get_nonce(c.dir.new_nonce) or {
			last_err = 'nonce: ${err}'
			if attempt + 1 < max_retry_attempts {
				c.log_warn('nonce fetch failed, retrying',
					err:    '${err}'
					detail: 'attempt ${attempt + 1}/${max_retry_attempts}'
				)
				time.sleep(backoff_ms(attempt) * time.millisecond)
				continue
			}
			return error('nonce fetch failed after ${max_retry_attempts} attempts: ${err}')
		}

		body := sign_jws(url, payload, nonce, c.account_kid, c.account_privkey) or {
			return error('jws signing failed: ${err}')
		}

		resp := acme_post(url, body) or {
			last_err = '${err}'
			if attempt + 1 < max_retry_attempts {
				c.log_warn('acme post failed, retrying',
					err:    '${err}'
					detail: 'attempt ${attempt + 1}/${max_retry_attempts}'
				)
				time.sleep(backoff_ms(attempt) * time.millisecond)
				continue
			}
			return error('acme post failed after ${max_retry_attempts} attempts: ${err}')
		}

		if is_bad_nonce(resp) {
			last_err = 'badNonce (HTTP 400)'
			c.log_warn('bad nonce, retrying with fresh nonce',
				detail: 'attempt ${attempt + 1}/${max_retry_attempts}'
			)
			continue
		}

		if is_retryable_status(resp.status_code) && attempt + 1 < max_retry_attempts {
			wait := retry_wait_ms(resp, attempt)
			c.log_warn('retryable status ${resp.status_code}, retrying',
				detail: 'attempt ${attempt + 1}/${max_retry_attempts}, wait ${wait}ms'
			)
			time.sleep(wait * time.millisecond)
			continue
		}

		return resp
	}
	return error('${last_err} (after ${max_retry_attempts} attempts)')
}
