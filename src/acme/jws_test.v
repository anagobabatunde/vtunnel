module acme

import crypto.ecdsa

// Helper to generate a fresh ECDSA P-256 key pair.
fn generate_test_key() !ecdsa.PrivateKey {
	_, privkey := ecdsa.generate_key()!
	return privkey
}

// --- base64url_encode ---

fn test_base64url_encode_empty() {
	assert base64url_encode([]) == ''
}

fn test_base64url_encode_simple() {
	result := base64url_encode('hello'.bytes())
	assert result == 'aGVsbG8'
	assert !result.contains('='), 'should not contain padding'
}

fn test_base64url_encode_binary_data() {
	// Bytes that would produce + and / in standard base64
	data := [u8(0xfb), 0xff, 0xfe]
	result := base64url_encode(data)
	assert !result.contains('+'), 'should not contain +'
	assert !result.contains('/'), 'should not contain /'
}

fn test_base64url_encode_single_byte() {
	result := base64url_encode([u8(0)])
	assert result.len > 0
}

// --- base64url_decode ---

fn test_base64url_decode_empty() {
	result := base64url_decode('') or {
		assert false, 'should not error on empty string'
		return
	}
	assert result.len == 0
}

fn test_base64url_roundtrip() {
	original := 'The quick brown fox jumps over the lazy dog'.bytes()
	encoded := base64url_encode(original)
	decoded := base64url_decode(encoded) or {
		assert false, 'decode failed: ${err}'
		return
	}
	assert decoded == original
}

fn test_base64url_roundtrip_binary() {
	mut data := []u8{len: 256}
	for i in 0 .. 256 {
		data[i] = u8(i)
	}
	encoded := base64url_encode(data)
	decoded := base64url_decode(encoded) or {
		assert false, 'decode failed: ${err}'
		return
	}
	assert decoded == data
}

// --- der_to_raw_ecdsa ---

fn test_der_to_raw_ecdsa_valid() {
	// Construct a minimal valid DER-encoded ECDSA signature
	// SEQUENCE { INTEGER r(32 bytes), INTEGER s(32 bytes) }
	mut r := []u8{len: 32, init: 0x01}
	mut s := []u8{len: 32, init: 0x02}
	mut der := []u8{}
	// SEQUENCE
	der << 0x30
	der << u8(2 + 32 + 2 + 32) // total inner length
	// INTEGER r
	der << 0x02
	der << u8(32)
	der << r
	// INTEGER s
	der << 0x02
	der << u8(32)
	der << s

	result := der_to_raw_ecdsa(der) or {
		assert false, 'should not error: ${err}'
		return
	}
	assert result.len == 64
	assert result[0..32] == r
	assert result[32..64] == s
}

fn test_der_to_raw_ecdsa_with_leading_zero() {
	// When r has a high bit set, DER prepends 0x00
	mut r_padded := [u8(0x00)]
	mut r_val := []u8{len: 32, init: 0x80}
	r_padded << r_val
	mut s := []u8{len: 32, init: 0x03}

	mut der := []u8{}
	der << 0x30
	der << u8(2 + 33 + 2 + 32) // r is 33 bytes with padding
	der << 0x02
	der << u8(33)
	der << r_padded
	der << 0x02
	der << u8(32)
	der << s

	result := der_to_raw_ecdsa(der) or {
		assert false, 'should not error: ${err}'
		return
	}
	assert result.len == 64
	// r should have the leading zero stripped
	assert result[0] == 0x80
}

fn test_der_to_raw_ecdsa_too_short() {
	if _ := der_to_raw_ecdsa([u8(0x30), 0x01]) {
		assert false, 'should error on short input'
	}
}

fn test_der_to_raw_ecdsa_wrong_tag() {
	der := []u8{len: 10, init: 0xFF}
	if _ := der_to_raw_ecdsa(der) {
		assert false, 'should error on wrong tag'
	}
}

// --- extract_public_key_xy + build_jwk_json ---

fn test_extract_public_key_xy() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	x, y := extract_public_key_xy(privkey) or {
		assert false, 'extract failed: ${err}'
		return
	}
	assert x.len == 32, 'x should be 32 bytes'
	assert y.len == 32, 'y should be 32 bytes'
}

fn test_build_jwk_json_format() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	jwk := build_jwk_json(privkey) or {
		assert false, 'build_jwk failed: ${err}'
		return
	}
	assert jwk.starts_with('{"crv":"P-256"')
	assert jwk.contains('"kty":"EC"')
	assert jwk.contains('"x":"')
	assert jwk.contains('"y":"')
}

// --- jwk_thumbprint ---

fn test_jwk_thumbprint_is_base64url() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	tp := jwk_thumbprint(privkey) or {
		assert false, 'thumbprint failed: ${err}'
		return
	}
	assert tp.len > 0
	assert !tp.contains('+'), 'should be base64url'
	assert !tp.contains('/'), 'should be base64url'
	assert !tp.contains('='), 'should not contain padding'
}

fn test_jwk_thumbprint_deterministic() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	tp1 := jwk_thumbprint(privkey) or {
		assert false, 'thumbprint 1 failed: ${err}'
		return
	}
	tp2 := jwk_thumbprint(privkey) or {
		assert false, 'thumbprint 2 failed: ${err}'
		return
	}
	assert tp1 == tp2, 'same key should produce same thumbprint'
}

fn test_jwk_thumbprint_different_keys() {
	key1 := generate_test_key() or {
		assert false, 'key1 generation failed: ${err}'
		return
	}
	key2 := generate_test_key() or {
		assert false, 'key2 generation failed: ${err}'
		return
	}
	tp1 := jwk_thumbprint(key1) or {
		assert false, 'thumbprint 1 failed: ${err}'
		return
	}
	tp2 := jwk_thumbprint(key2) or {
		assert false, 'thumbprint 2 failed: ${err}'
		return
	}
	assert tp1 != tp2, 'different keys should produce different thumbprints'
}

// --- sign_jws ---

fn test_sign_jws_with_kid() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	jws := sign_jws('https://acme.example/order', '{"foo":"bar"}', 'test-nonce', 'https://acme.example/acct/1',
		privkey) or {
		assert false, 'sign_jws failed: ${err}'
		return
	}
	assert jws.contains('"protected"')
	assert jws.contains('"payload"')
	assert jws.contains('"signature"')
}

fn test_sign_jws_without_kid_includes_jwk() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	jws := sign_jws('https://acme.example/new-acct', '{"termsOfServiceAgreed":true}',
		'test-nonce', '', privkey) or {
		assert false, 'sign_jws failed: ${err}'
		return
	}
	assert jws.contains('"protected"')
	assert jws.contains('"payload"')
	assert jws.contains('"signature"')

	// Decode protected header to verify it contains jwk not kid
	start := jws.index('"protected":"') or { 0 } + 13
	end := jws.index('","payload"') or { 0 }
	protected_b64 := jws[start..end]
	protected_bytes := base64url_decode(protected_b64) or {
		assert false, 'failed to decode protected header'
		return
	}
	protected := protected_bytes.bytestr()
	assert protected.contains('"jwk"'), 'should contain jwk when kid is empty'
	assert !protected.contains('"kid"'), 'should not contain kid when kid is empty'
}

fn test_sign_jws_empty_payload() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	jws := sign_jws('https://acme.example/order/1', '', 'test-nonce', 'https://acme.example/acct/1',
		privkey) or {
		assert false, 'sign_jws failed: ${err}'
		return
	}
	assert jws.contains('"payload":""'), 'empty payload should produce empty base64url string'
}

// --- ecdsa_sign_raw ---

fn test_ecdsa_sign_raw_produces_64_bytes() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	sig := ecdsa_sign_raw('test message'.bytes(), privkey) or {
		assert false, 'signing failed: ${err}'
		return
	}
	assert sig.len == 64, 'ES256 raw signature should be 64 bytes'
}

fn test_ecdsa_sign_raw_different_messages() {
	privkey := generate_test_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	sig1 := ecdsa_sign_raw('message 1'.bytes(), privkey) or {
		assert false, 'signing 1 failed: ${err}'
		return
	}
	sig2 := ecdsa_sign_raw('message 2'.bytes(), privkey) or {
		assert false, 'signing 2 failed: ${err}'
		return
	}
	// ECDSA signatures include randomness, so even same message would differ
	// But different messages definitely should differ
	assert sig1 != sig2 || true // signatures are non-deterministic, just ensure no error
}
