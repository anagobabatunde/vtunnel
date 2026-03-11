module acme

import crypto.ecdsa
import net.http
import os
import src.slog
import time

// ACME directory URLs
const le_production_url = 'https://acme-v02.api.letsencrypt.org/directory'
const le_staging_url = 'https://acme-staging-v02.api.letsencrypt.org/directory'

// Directory holds the ACME server endpoint URLs discovered from the directory.
struct Directory {
mut:
	new_nonce   string
	new_account string
	new_order   string
}

// AcmeClient orchestrates the ACME protocol flow for obtaining and renewing TLS certificates.
@[heap]
pub struct AcmeClient {
pub mut:
	directory_url   string
	domain          string
	email           string
	acme_dir        string // local cert storage directory
	account_privkey ecdsa.PrivateKey
	account_kid     string // ACME account URL
	challenge_store &ChallengeStore
	dir             Directory
	logger          &slog.Logger = unsafe { nil }
}

// new_client creates a new ACME client for the given domain.
// Set staging=true to use the Let's Encrypt staging environment.
pub fn new_client(domain string, email string, acme_dir string, staging bool, store &ChallengeStore, privkey ecdsa.PrivateKey) &AcmeClient {
	dir_url := if staging { le_staging_url } else { le_production_url }
	return &AcmeClient{
		directory_url:   dir_url
		domain:          domain
		email:           email
		acme_dir:        acme_dir
		challenge_store: store
		account_privkey: privkey
	}
}

// log_info logs a message at info level if a logger is configured.
fn (c &AcmeClient) log_info(msg string, params slog.LogParams) {
	if c.logger != unsafe { nil } {
		c.logger.info(msg, params)
	}
}

// log_warn logs a message at warn level if a logger is configured.
fn (c &AcmeClient) log_warn(msg string, params slog.LogParams) {
	if c.logger != unsafe { nil } {
		c.logger.warn(msg, params)
	}
}

// log_error logs a message at error level if a logger is configured.
fn (c &AcmeClient) log_error(msg string, params slog.LogParams) {
	if c.logger != unsafe { nil } {
		c.logger.error(msg, params)
	}
}

// discover fetches the ACME directory to learn endpoint URLs.
pub fn (mut c AcmeClient) discover() ! {
	resp := http_get_with_retry(c.directory_url) or {
		return error('failed to fetch ACME directory: ${err}')
	}
	if resp.status_code != 200 {
		return error('ACME directory returned ${resp.status_code}')
	}
	c.dir.new_nonce = json_string_field(resp.body, 'newNonce')
	c.dir.new_account = json_string_field(resp.body, 'newAccount')
	c.dir.new_order = json_string_field(resp.body, 'newOrder')

	if c.dir.new_nonce.len == 0 || c.dir.new_account.len == 0 || c.dir.new_order.len == 0 {
		return error('ACME directory missing required endpoints')
	}
}

// register_or_load_account loads an existing account key/kid or creates a new one.
pub fn (mut c AcmeClient) register_or_load_account() ! {
	ensure_dir(c.acme_dir)!

	key_path := os.join_path(c.acme_dir, 'account.key')
	kid_path := os.join_path(c.acme_dir, 'account.kid')

	if os.exists(key_path) && os.exists(kid_path) {
		c.account_privkey = load_account_key(key_path)!
		c.account_kid = load_account_kid(kid_path)!
		c.log_info('loaded existing account', detail: c.account_kid)
		return
	}

	// Generate new account key
	c.account_privkey = generate_account_key()!
	save_account_key(key_path, c.account_privkey)!

	// Register with ACME server
	c.account_kid = c.register_account()!
	save_account_kid(kid_path, c.account_kid)!
	c.log_info('registered new account', detail: c.account_kid)
}

// register_account creates a new ACME account and returns the account URL (kid).
fn (mut c AcmeClient) register_account() !string {
	payload := '{"termsOfServiceAgreed":true,"contact":["mailto:${c.email}"]}'
	resp := c.signed_post(c.dir.new_account, payload)!
	if resp.status_code != 201 && resp.status_code != 200 {
		return error('account registration failed (${resp.status_code}): ${resp.body}')
	}

	kid := resp.header.get(.location) or { return error('no Location header in account response') }
	return kid
}

// obtain_certificate performs the full ACME flow to obtain a certificate for the domain.
pub fn (mut c AcmeClient) obtain_certificate() !CertInfo {
	domain_dir := os.join_path(c.acme_dir, c.domain)
	ensure_dir(domain_dir)!

	// Generate domain key pair
	_, domain_privkey := ecdsa.generate_key()!
	domain_key_path := os.join_path(domain_dir, 'domain.key')
	save_account_key(domain_key_path, domain_privkey)!

	// 1. Create order
	auth_urls, finalize_url := c.create_order()!
	c.log_info('order created, ${auth_urls.len} authorization(s)')

	// 2. Process each authorization
	for auth_url in auth_urls {
		c.process_authorization(auth_url)!
	}

	// 3. Finalize order with CSR
	cert_url := c.finalize_order(finalize_url, domain_privkey)!

	// 4. Download certificate
	cert_pem := c.download_certificate(cert_url)!
	cert_path := os.join_path(domain_dir, 'fullchain.pem')
	save_certificate(cert_path, cert_pem)!
	c.log_info('certificate saved', detail: cert_path)

	not_after := parse_not_after_from_pem(cert_pem) or {
		c.log_warn('could not parse certificate expiry, using 90 day default')
		time.now().add(90 * 24 * time.hour)
	}

	return CertInfo{
		cert_path: cert_path
		key_path:  domain_key_path
		domain:    c.domain
		not_after: not_after
	}
}

// create_order creates a new ACME order for the domain.
// Returns (authorization_urls, finalize_url).
fn (mut c AcmeClient) create_order() !([]string, string) {
	payload := '{"identifiers":[{"type":"dns","value":"${c.domain}"}]}'
	resp := c.signed_post(c.dir.new_order, payload)!
	if resp.status_code != 201 {
		return error('create order failed (${resp.status_code}): ${resp.body}')
	}

	finalize_url := json_string_field(resp.body, 'finalize')
	auth_urls := json_string_array_field(resp.body, 'authorizations')

	if finalize_url.len == 0 || auth_urls.len == 0 {
		return error('order response missing finalize or authorizations')
	}

	return auth_urls, finalize_url
}

// process_authorization handles a single authorization by finding and responding to
// the HTTP-01 challenge.
fn (mut c AcmeClient) process_authorization(auth_url string) ! {
	resp := c.signed_post(auth_url, '')!
	if resp.status_code != 200 {
		return error('fetch authorization failed (${resp.status_code}): ${resp.body}')
	}

	// Find HTTP-01 challenge
	challenge_url, token := find_http01_challenge(resp.body)!

	// Compute key authorization and set it in the challenge store
	thumbprint := jwk_thumbprint(c.account_privkey)!
	key_auth := key_authorization(token, thumbprint)
	c.challenge_store.set(token, key_auth)
	defer {
		c.challenge_store.remove(token)
	}

	// Notify ACME server we're ready
	c.respond_to_challenge(challenge_url)!

	// Poll until challenge is valid or fails
	c.poll_challenge(auth_url)!
}

// respond_to_challenge tells the ACME server we're ready for validation.
fn (mut c AcmeClient) respond_to_challenge(challenge_url string) ! {
	resp := c.signed_post(challenge_url, '{}')!
	if resp.status_code != 200 {
		return error('challenge response failed (${resp.status_code}): ${resp.body}')
	}
}

// poll_challenge polls the authorization URL until the status is "valid" or an error occurs.
fn (mut c AcmeClient) poll_challenge(auth_url string) ! {
	mut transient_errors := 0
	for attempt in 0 .. 30 {
		time.sleep(2 * time.second)

		resp := c.signed_post(auth_url, '') or {
			transient_errors++
			if transient_errors > max_poll_transient {
				return error('poll authorization: too many transient errors: ${err}')
			}
			c.log_warn('poll authorization transient error',
				err:    '${err}'
				detail: 'attempt ${attempt + 1}'
			)
			continue
		}

		if resp.status_code != 200 {
			return error('poll authorization failed (${resp.status_code})')
		}

		transient_errors = 0
		status := json_string_field(resp.body, 'status')

		if status == 'valid' {
			c.log_info('authorization validated', detail: 'attempt ${attempt + 1}')
			return
		}
		if status == 'invalid' {
			return error('authorization failed: challenge invalid')
		}
	}
	return error('authorization timed out after 60 seconds')
}

// finalize_order submits the CSR to finalize the order and returns the certificate URL.
fn (mut c AcmeClient) finalize_order(finalize_url string, domain_privkey ecdsa.PrivateKey) !string {
	csr_der := generate_csr(c.domain, domain_privkey)!
	csr_b64 := base64url_encode(csr_der)

	payload := '{"csr":"${csr_b64}"}'
	resp := c.signed_post(finalize_url, payload)!
	if resp.status_code != 200 {
		return error('finalize order failed (${resp.status_code}): ${resp.body}')
	}

	return c.poll_order_for_cert(resp)
}

// poll_order_for_cert polls the order until a certificate URL is available.
fn (mut c AcmeClient) poll_order_for_cert(initial_resp http.Response) !string {
	mut last_body := initial_resp.body
	mut order_url := initial_resp.header.get(.location) or { '' }
	mut transient_errors := 0

	for _ in 0 .. 30 {
		status := json_string_field(last_body, 'status')

		if status == 'valid' {
			cert_url := json_string_field(last_body, 'certificate')
			if cert_url.len > 0 {
				return cert_url
			}
		}
		if status == 'invalid' {
			return error('order failed: status invalid')
		}

		if order_url.len == 0 {
			return error('no order URL for polling')
		}

		time.sleep(2 * time.second)

		resp := c.signed_post(order_url, '') or {
			transient_errors++
			if transient_errors > max_poll_transient {
				return error('poll order: too many transient errors: ${err}')
			}
			c.log_warn('poll order transient error',
				err:    '${err}'
				detail: 'order ${order_url}'
			)
			continue
		}
		transient_errors = 0
		last_body = resp.body
		order_url = resp.header.get(.location) or { order_url }
	}
	return error('order finalization timed out')
}

// download_certificate downloads the certificate PEM from the given URL.
fn (mut c AcmeClient) download_certificate(cert_url string) !string {
	resp := c.signed_post(cert_url, '')!
	if resp.status_code != 200 {
		return error('download certificate failed (${resp.status_code}): ${resp.body}')
	}

	return resp.body
}

// renew_if_needed checks if the certificate needs renewal and renews if so.
pub fn (mut c AcmeClient) renew_if_needed(renew_before time.Duration) !bool {
	domain_dir := os.join_path(c.acme_dir, c.domain)
	cert_path := os.join_path(domain_dir, 'fullchain.pem')
	key_path := os.join_path(domain_dir, 'domain.key')

	if !os.exists(cert_path) || !os.exists(key_path) {
		c.obtain_certificate()!
		return true
	}

	info := load_cert_info(cert_path, key_path, c.domain)!
	if !cert_needs_renewal(info, renew_before) {
		return false
	}

	c.log_info('certificate expires ${info.not_after}, renewing')
	c.obtain_certificate()!
	return true
}

// run_renewal_loop periodically checks and renews the certificate.
// Runs forever — should be spawned in a goroutine.
pub fn (mut c AcmeClient) run_renewal_loop(check_interval time.Duration, renew_before time.Duration, on_renewed fn (CertInfo)) {
	mut consecutive_failures := 0
	for {
		// On consecutive failures, use exponential backoff instead of the normal interval
		wait := if consecutive_failures > 0 {
			secs := renewal_backoff(consecutive_failures)
			c.log_info('renewal retry backoff',
				detail: '${secs}s after ${consecutive_failures} failure(s)'
			)
			secs * time.second
		} else {
			check_interval
		}
		time.sleep(wait)

		renewed := c.renew_if_needed(renew_before) or {
			consecutive_failures++
			c.log_error('renewal check failed',
				err:    '${err}'
				detail: 'failure ${consecutive_failures}'
			)
			continue
		}

		consecutive_failures = 0

		if renewed {
			domain_dir := os.join_path(c.acme_dir, c.domain)
			cert_path := os.join_path(domain_dir, 'fullchain.pem')
			key_path := os.join_path(domain_dir, 'domain.key')
			info := load_cert_info(cert_path, key_path, c.domain) or {
				c.log_error('failed to load renewed cert info', err: '${err}')
				continue
			}
			on_renewed(info)
		}
	}
}

// --- Simple JSON helpers (no dependency on json module for dynamic parsing) ---

// json_string_field extracts a string value for a given key from a JSON object string.
// Uses simple string scanning — sufficient for ACME responses.
fn json_string_field(json_body string, key string) string {
	search := '"${key}"'
	idx := json_body.index(search) or { return '' }
	// Skip past the key and colon
	rest := json_body[idx + search.len..]
	colon_idx := rest.index(':') or { return '' }
	after_colon := rest[colon_idx + 1..].trim_left(' \t')
	if after_colon.len == 0 || after_colon[0] != `"` {
		return ''
	}
	// Find closing quote (handle escaped quotes)
	mut end := 1
	for end < after_colon.len {
		if after_colon[end] == `"` && (end == 0 || after_colon[end - 1] != `\\`) {
			break
		}
		end++
	}
	return after_colon[1..end]
}

// json_string_array_field extracts an array of strings for a given key from a JSON object.
fn json_string_array_field(json_body string, key string) []string {
	search := '"${key}"'
	idx := json_body.index(search) or { return [] }
	rest := json_body[idx + search.len..]
	bracket_idx := rest.index('[') or { return [] }
	end_bracket := rest.index(']') or { return [] }
	arr_str := rest[bracket_idx + 1..end_bracket]

	mut result := []string{}
	mut in_string := false
	mut start := 0
	for i, ch in arr_str {
		if ch == `"` && !in_string {
			in_string = true
			start = i + 1
		} else if ch == `"` && in_string {
			in_string = false
			result << arr_str[start..i]
		}
	}
	return result
}

// find_http01_challenge finds the HTTP-01 challenge URL and token from an authorization response.
fn find_http01_challenge(json_body string) !(string, string) {
	// Find "challenges" array, then locate the http-01 challenge
	challenges_idx := json_body.index('"challenges"') or {
		return error('no challenges field in authorization')
	}
	challenges_rest := json_body[challenges_idx..]

	// Find all challenge objects by scanning for "type":"http-01"
	http01_idx := challenges_rest.index('"http-01"') or {
		return error('no http-01 challenge found')
	}

	// Extract the enclosing challenge object
	// Look backward from http01_idx for the opening brace
	mut obj_start := http01_idx
	for obj_start > 0 && challenges_rest[obj_start] != `{` {
		obj_start--
	}
	// Look forward for the closing brace
	mut obj_end := http01_idx
	for obj_end < challenges_rest.len && challenges_rest[obj_end] != `}` {
		obj_end++
	}
	if obj_end < challenges_rest.len {
		obj_end++
	}

	challenge_obj := challenges_rest[obj_start..obj_end]
	url := json_string_field(challenge_obj, 'url')
	token := json_string_field(challenge_obj, 'token')

	if url.len == 0 || token.len == 0 {
		return error('http-01 challenge missing url or token')
	}

	return url, token
}

// acme_post sends a POST request with the JWS body and ACME-required content type.
fn acme_post(url string, body string) !http.Response {
	mut req := http.new_request(.post, url, body)
	req.add_custom_header('Content-Type', 'application/jose+json') or {}
	return req.do()!
}
