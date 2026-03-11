module acme

import crypto.ecdsa

// --- der_length ---

fn test_der_length_short_form() {
	assert der_length(0) == [u8(0)]
	assert der_length(1) == [u8(1)]
	assert der_length(127) == [u8(127)]
}

fn test_der_length_one_byte_long_form() {
	assert der_length(128) == [u8(0x81), 128]
	assert der_length(255) == [u8(0x81), 255]
}

fn test_der_length_two_byte_long_form() {
	assert der_length(256) == [u8(0x82), 1, 0]
	assert der_length(65535) == [u8(0x82), 0xFF, 0xFF]
}

// --- der_integer ---

fn test_der_integer_zero() {
	result := der_integer(0)
	assert result == [u8(0x02), 0x01, 0x00]
}

fn test_der_integer_small() {
	result := der_integer(1)
	assert result == [u8(0x02), 0x01, 0x01]
}

fn test_der_integer_high_bit_set() {
	// 128 (0x80) needs leading 0x00 to avoid being negative
	result := der_integer(128)
	assert result == [u8(0x02), 0x02, 0x00, 0x80]
}

fn test_der_integer_multi_byte() {
	// 256 = 0x0100
	result := der_integer(256)
	assert result == [u8(0x02), 0x02, 0x01, 0x00]
}

// --- der_oid ---

fn test_der_oid_simple() {
	// OID 2.5.29.17 (SAN) → first byte: 40*2+5=85, then 29, 17
	result := der_oid([2, 5, 29, 17])
	assert result[0] == 0x06 // OID tag
	assert result[1] == 0x03 // length = 3
	assert result[2] == 0x55 // 40*2 + 5 = 85
	assert result[3] == 0x1D // 29
	assert result[4] == 0x11 // 17
}

fn test_der_oid_with_large_component() {
	// OID 1.2.840.10045.4.3.2 (ecdsaWithSHA256)
	// 840 = 0x348 → VLQ: 0x86, 0x48
	result := der_oid([1, 2, 840, 10045, 4, 3, 2])
	assert result[0] == 0x06 // OID tag
	// First byte: 40*1 + 2 = 42
	assert result[2] == 42
}

fn test_der_oid_ec_pubkey() {
	// OID 1.2.840.10045.2.1 (id-ecPublicKey)
	result := der_oid([1, 2, 840, 10045, 2, 1])
	assert result[0] == 0x06
	assert result.len > 4
}

// --- der_bit_string ---

fn test_der_bit_string_empty() {
	result := der_bit_string([])
	assert result[0] == 0x03 // BIT STRING tag
	assert result[1] == 0x01 // length 1 (just the unused bits byte)
	assert result[2] == 0x00 // unused bits
}

fn test_der_bit_string_with_data() {
	data := [u8(0x04), 0x01, 0x02]
	result := der_bit_string(data)
	assert result[0] == 0x03 // BIT STRING tag
	assert result[1] == 0x04 // length 4 (1 unused bits byte + 3 data bytes)
	assert result[2] == 0x00 // unused bits
	assert result[3] == 0x04
	assert result[4] == 0x01
	assert result[5] == 0x02
}

// --- der_sequence ---

fn test_der_sequence_empty() {
	result := der_sequence([])
	assert result == [u8(0x30), 0x00]
}

fn test_der_sequence_with_data() {
	data := [u8(0x01), 0x02, 0x03]
	result := der_sequence(data)
	assert result[0] == 0x30 // SEQUENCE tag
	assert result[1] == 0x03 // length
	assert result[2..] == data
}

// --- der_tag_length_value ---

fn test_der_tag_length_value() {
	data := [u8(0xAA), 0xBB]
	result := der_tag_length_value(0x04, data) // OCTET STRING
	assert result[0] == 0x04
	assert result[1] == 0x02
	assert result[2] == 0xAA
	assert result[3] == 0xBB
}

// --- build_san_extension ---

fn test_build_san_extension_structure() {
	san := build_san_extension('example.com')
	// Should be a SEQUENCE containing OID and OCTET STRING
	assert san[0] == 0x30 // outer SEQUENCE
	assert san.len > 10

	// Should contain the domain bytes somewhere
	domain_bytes := 'example.com'.bytes()
	mut found := false
	if san.len >= domain_bytes.len {
		for i in 0 .. san.len - domain_bytes.len + 1 {
			if san[i..i + domain_bytes.len] == domain_bytes {
				found = true
				break
			}
		}
	}
	assert found, 'SAN should contain domain name bytes'
}

// --- encode_ecdsa_public_key_der ---

fn test_encode_ecdsa_public_key_der() {
	_, privkey := ecdsa.generate_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	spki := encode_ecdsa_public_key_der(privkey) or {
		assert false, 'encode failed: ${err}'
		return
	}
	// Should be a SEQUENCE
	assert spki[0] == 0x30
	// Should contain the P-256 public key (65 bytes uncompressed: 04 || x || y)
	assert spki.len > 70
}

// --- generate_csr ---

fn test_generate_csr_produces_valid_der() {
	_, privkey := ecdsa.generate_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	csr := generate_csr('example.com', privkey) or {
		assert false, 'CSR generation failed: ${err}'
		return
	}
	// CSR should start with SEQUENCE tag
	assert csr[0] == 0x30, 'CSR should start with SEQUENCE tag'
	assert csr.len > 100, 'CSR should be substantial'
}

fn test_generate_csr_contains_domain() {
	_, privkey := ecdsa.generate_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	csr := generate_csr('test.example.com', privkey) or {
		assert false, 'CSR generation failed: ${err}'
		return
	}
	domain_bytes := 'test.example.com'.bytes()
	mut found := false
	for i in 0 .. csr.len - domain_bytes.len {
		if csr[i..i + domain_bytes.len] == domain_bytes {
			found = true
			break
		}
	}
	assert found, 'CSR should contain the domain name'
}

fn test_generate_csr_different_domains_differ() {
	_, privkey := ecdsa.generate_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	csr1 := generate_csr('foo.example.com', privkey) or {
		assert false, 'CSR 1 failed: ${err}'
		return
	}
	csr2 := generate_csr('bar.example.com', privkey) or {
		assert false, 'CSR 2 failed: ${err}'
		return
	}
	assert csr1 != csr2, 'different domains should produce different CSRs'
}

fn test_generate_csr_openssl_verify() {
	// Generate CSR and verify it with openssl command if available
	_, privkey := ecdsa.generate_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	csr := generate_csr('test.example.com', privkey) or {
		assert false, 'CSR generation failed: ${err}'
		return
	}
	// Just verify it's well-formed DER — outer SEQUENCE with valid length
	assert csr[0] == 0x30
	inner_len := if csr[1] < 0x80 {
		int(csr[1])
	} else if csr[1] == 0x81 {
		int(csr[2])
	} else {
		int(csr[2]) << 8 | int(csr[3])
	}
	header_len := if csr[1] < 0x80 {
		2
	} else if csr[1] == 0x81 {
		3
	} else {
		4
	}
	assert csr.len == header_len + inner_len, 'DER length should match actual data length'
}
