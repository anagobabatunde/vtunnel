module acme

import crypto.ecdsa
import crypto.sha256
import encoding.base64
import net.http

// base64url_encode encodes bytes to base64url (URL-safe, no padding) per RFC 4648 §5.
pub fn base64url_encode(data []u8) string {
	return base64.url_encode(data)
}

// base64url_decode decodes a base64url string back to bytes.
pub fn base64url_decode(s string) ![]u8 {
	return base64.url_decode(s)
}

// jwk_thumbprint computes the JWK Thumbprint (RFC 7638) of an ECDSA P-256 public key.
// The thumbprint is a base64url-encoded SHA-256 hash of the canonical JWK representation.
pub fn jwk_thumbprint(privkey ecdsa.PrivateKey) !string {
	jwk_json := build_jwk_json(privkey)!
	hash := sha256.sum(jwk_json.bytes())
	return base64url_encode(hash[..])
}

// sign_jws creates a JWS (JSON Web Signature) in flattened JSON serialization for ACME requests.
// Uses ES256 (ECDSA P-256 + SHA-256) algorithm.
// If kid is empty, includes the full JWK in the protected header (for new-account).
// If kid is set, includes kid instead of JWK (for all other requests).
pub fn sign_jws(url string, payload string, nonce string, kid string, privkey ecdsa.PrivateKey) !string {
	// Build protected header
	protected := if kid != '' {
		'{"alg":"ES256","kid":"${kid}","nonce":"${nonce}","url":"${url}"}'
	} else {
		jwk := build_jwk_json(privkey)!
		'{"alg":"ES256","jwk":${jwk},"nonce":"${nonce}","url":"${url}"}'
	}

	protected_b64 := base64url_encode(protected.bytes())
	payload_b64 := if payload != '' {
		base64url_encode(payload.bytes())
	} else {
		'' // empty payload for POST-as-GET
	}

	// Signing input: protected.payload (both base64url-encoded)
	signing_input := '${protected_b64}.${payload_b64}'
	sig := ecdsa_sign_raw(signing_input.bytes(), privkey)!
	sig_b64 := base64url_encode(sig)

	return '{"protected":"${protected_b64}","payload":"${payload_b64}","signature":"${sig_b64}"}'
}

// get_nonce fetches a fresh anti-replay nonce from the ACME server's newNonce endpoint.
pub fn get_nonce(new_nonce_url string) !string {
	resp := http.head(new_nonce_url) or { return error('failed to fetch nonce: ${err}') }
	nonce := resp.header.get_custom('Replay-Nonce') or {
		return error('no replay-nonce header in response')
	}
	return nonce
}

// ecdsa_sign_raw signs a message with ECDSA P-256 and returns a 64-byte raw r||s signature.
// ACME ES256 requires raw (r, s) concatenation, NOT ASN.1 DER encoding.
fn ecdsa_sign_raw(message []u8, privkey ecdsa.PrivateKey) ![]u8 {
	// V's ecdsa.sign() returns DER-encoded signature by default
	der_sig := privkey.sign(message)!
	// Parse DER to extract raw r and s values
	return der_to_raw_ecdsa(der_sig)
}

// der_to_raw_ecdsa converts a DER-encoded ECDSA signature to raw r||s format (64 bytes for P-256).
// DER structure: SEQUENCE { INTEGER r, INTEGER s }
fn der_to_raw_ecdsa(der []u8) ![]u8 {
	if der.len < 8 {
		return error('DER signature too short')
	}
	if der[0] != 0x30 {
		return error('expected SEQUENCE tag (0x30)')
	}

	mut pos := 2 // skip SEQUENCE tag + length

	// Parse r
	if der[pos] != 0x02 {
		return error('expected INTEGER tag for r')
	}
	pos++
	r_len := int(der[pos])
	pos++
	mut r := der[pos..pos + r_len].clone()
	pos += r_len

	// Parse s
	if der[pos] != 0x02 {
		return error('expected INTEGER tag for s')
	}
	pos++
	s_len := int(der[pos])
	pos++
	mut s := der[pos..pos + s_len].clone()

	// Strip leading zero byte (ASN.1 sign padding) if present
	if r.len == 33 && r[0] == 0x00 {
		r = r[1..].clone()
	}
	if s.len == 33 && s[0] == 0x00 {
		s = s[1..].clone()
	}

	// Pad to 32 bytes each if shorter (unlikely but possible)
	mut result := []u8{len: 64}
	r_offset := 32 - r.len
	for i in 0 .. r.len {
		result[r_offset + i] = r[i]
	}
	s_offset := 32 - s.len
	for i in 0 .. s.len {
		result[32 + s_offset + i] = s[i]
	}

	return result
}

// extract_public_key_xy extracts the x and y coordinates from an ECDSA P-256 public key.
// Returns (x, y) each as 32-byte big-endian arrays.
fn extract_public_key_xy(privkey ecdsa.PrivateKey) !([]u8, []u8) {
	pubkey := privkey.public_key()!
	pub_bytes := pubkey.bytes()!

	// Public key bytes: 0x04 || x (32 bytes) || y (32 bytes) for uncompressed point
	if pub_bytes.len < 65 || pub_bytes[0] != 0x04 {
		return error('unexpected public key format (expected uncompressed point)')
	}

	x := pub_bytes[1..33].clone()
	y := pub_bytes[33..65].clone()
	return x, y
}

// build_jwk_json builds the canonical JWK JSON representation of an ECDSA P-256 public key.
// Follows RFC 7638 lexicographic ordering: crv, kty, x, y.
fn build_jwk_json(privkey ecdsa.PrivateKey) !string {
	x, y := extract_public_key_xy(privkey)!
	x_b64 := base64url_encode(x)
	y_b64 := base64url_encode(y)
	return '{"crv":"P-256","kty":"EC","x":"${x_b64}","y":"${y_b64}"}'
}
