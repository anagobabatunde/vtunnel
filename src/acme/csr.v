module acme

import crypto.ecdsa

// generate_csr creates a minimal PKCS#10 Certificate Signing Request in DER format.
// The CSR contains only the domain in a Subject Alternative Name (SAN) extension,
// signed with the provided ECDSA P-256 private key using ecdsaWithSHA256.
pub fn generate_csr(domain string, privkey ecdsa.PrivateKey) ![]u8 {
	pub_key_der := encode_ecdsa_public_key_der(privkey)!

	// Build CertificationRequestInfo (the TBS portion)
	cri := build_certification_request_info(domain, pub_key_der)

	// Sign the CRI with the private key
	sig_der := privkey.sign(cri)!

	// Convert DER signature to raw r||s then back to DER BIT STRING
	// Note: the CSR signature uses DER-encoded ECDSA, not raw r||s
	sig_bits := der_bit_string(sig_der)

	// ecdsaWithSHA256 algorithm identifier OID: 1.2.840.10045.4.3.2
	sig_alg := der_sequence(der_oid([1, 2, 840, 10045, 4, 3, 2]))

	// Final CSR = SEQUENCE { CRI, signatureAlgorithm, signature }
	mut csr_inner := []u8{}
	csr_inner << cri
	csr_inner << sig_alg
	csr_inner << sig_bits

	return der_sequence(csr_inner)
}

// build_certification_request_info builds the CertificationRequestInfo structure.
// Structure: SEQUENCE { version(0), subject(empty), subjectPKInfo, attributes[SAN] }
fn build_certification_request_info(domain string, pub_key_der []u8) []u8 {
	// Version: INTEGER 0
	version := der_integer(0)

	// Subject: SEQUENCE {} (empty — domain goes in SAN extension)
	subject := der_sequence([]u8{})

	// SubjectPublicKeyInfo: already DER-encoded
	spki := pub_key_der

	// Attributes [0] IMPLICIT with extensionRequest containing SAN
	san_ext := build_san_extension(domain)

	// extensionRequest OID: 1.2.840.113549.1.9.14
	ext_req_oid := der_oid([1, 2, 840, 113549, 1, 9, 14])

	// SET { SEQUENCE { extensions } }
	ext_seq := der_sequence(san_ext)
	ext_set := der_tag_length_value(0x31, ext_seq) // SET

	// SEQUENCE { OID, SET { SEQUENCE { ext } } }
	mut attr_inner := []u8{}
	attr_inner << ext_req_oid
	attr_inner << ext_set
	attr_seq := der_sequence(attr_inner)

	// Wrap in context [0] CONSTRUCTED
	attributes := der_tag_length_value(0xA0, attr_seq)

	// CertificationRequestInfo = SEQUENCE { version, subject, spki, attributes }
	mut cri_inner := []u8{}
	cri_inner << version
	cri_inner << subject
	cri_inner << spki
	cri_inner << attributes

	return der_sequence(cri_inner)
}

// build_san_extension builds the Subject Alternative Name extension for a domain.
// Returns a SEQUENCE { OID, OCTET STRING { GeneralNames } }.
fn build_san_extension(domain string) []u8 {
	// SAN OID: 2.5.29.17
	san_oid := der_oid([2, 5, 29, 17])

	// GeneralNames: SEQUENCE { dNSName [2] IMPLICIT IA5String }
	dns_name := der_tag_length_value(0x82, domain.bytes()) // context [2] for dNSName
	general_names := der_sequence(dns_name)

	// Wrap in OCTET STRING
	san_value := der_tag_length_value(0x04, general_names) // OCTET STRING

	// Extension = SEQUENCE { OID, value }
	mut ext_inner := []u8{}
	ext_inner << san_oid
	ext_inner << san_value

	return der_sequence(ext_inner)
}

// encode_ecdsa_public_key_der builds the SubjectPublicKeyInfo DER for an ECDSA P-256 key.
// Structure: SEQUENCE { AlgorithmIdentifier, BIT STRING { uncompressed point } }
fn encode_ecdsa_public_key_der(privkey ecdsa.PrivateKey) ![]u8 {
	pubkey := privkey.public_key()!
	pub_bytes := pubkey.bytes()!

	// AlgorithmIdentifier: SEQUENCE { id-ecPublicKey OID, prime256v1 OID }
	ec_pubkey_oid := der_oid([1, 2, 840, 10045, 2, 1]) // id-ecPublicKey
	p256_oid := der_oid([1, 2, 840, 10045, 3, 1, 7]) // prime256v1 (P-256)
	mut alg_inner := []u8{}
	alg_inner << ec_pubkey_oid
	alg_inner << p256_oid
	alg_id := der_sequence(alg_inner)

	// BIT STRING containing the uncompressed public key point
	pub_bits := der_bit_string(pub_bytes)

	mut spki_inner := []u8{}
	spki_inner << alg_id
	spki_inner << pub_bits

	return der_sequence(spki_inner)
}

// --- DER encoding helpers ---

// der_sequence wraps data in an ASN.1 SEQUENCE (tag 0x30).
fn der_sequence(data []u8) []u8 {
	return der_tag_length_value(0x30, data)
}

// der_tag_length_value constructs a TLV (Tag-Length-Value) ASN.1 element.
fn der_tag_length_value(tag u8, data []u8) []u8 {
	mut result := []u8{}
	result << tag
	result << der_length(data.len)
	result << data
	return result
}

// der_length encodes a length in DER format.
// Short form: length < 128 → single byte.
// Long form: length >= 128 → 0x80|n followed by n bytes of length.
fn der_length(length int) []u8 {
	if length < 128 {
		return [u8(length)]
	}
	if length < 256 {
		return [u8(0x81), u8(length)]
	}
	if length < 65536 {
		return [u8(0x82), u8(length >> 8), u8(length & 0xFF)]
	}
	return [u8(0x83), u8(length >> 16), u8((length >> 8) & 0xFF), u8(length & 0xFF)]
}

// der_oid encodes an OID (Object Identifier) in DER format.
fn der_oid(components []int) []u8 {
	if components.len < 2 {
		return []u8{}
	}

	mut encoded := []u8{}
	// First two components are combined: 40*first + second
	encoded << u8(40 * components[0] + components[1])

	// Remaining components use base-128 VLQ encoding
	for i in 2 .. components.len {
		val := components[i]
		if val < 128 {
			encoded << u8(val)
		} else if val < 16384 {
			encoded << u8(0x80 | (val >> 7))
			encoded << u8(val & 0x7F)
		} else if val < 2097152 {
			encoded << u8(0x80 | (val >> 14))
			encoded << u8(0x80 | ((val >> 7) & 0x7F))
			encoded << u8(val & 0x7F)
		} else {
			encoded << u8(0x80 | (val >> 21))
			encoded << u8(0x80 | ((val >> 14) & 0x7F))
			encoded << u8(0x80 | ((val >> 7) & 0x7F))
			encoded << u8(val & 0x7F)
		}
	}

	return der_tag_length_value(0x06, encoded)
}

// der_bit_string wraps data in an ASN.1 BIT STRING (tag 0x03).
// Prepends a 0x00 byte for unused bits count (always 0 for byte-aligned data).
fn der_bit_string(data []u8) []u8 {
	mut padded := [u8(0x00)] // unused bits = 0
	padded << data
	return der_tag_length_value(0x03, padded)
}

// der_integer encodes a non-negative integer in DER format.
fn der_integer(value int) []u8 {
	if value == 0 {
		return der_tag_length_value(0x02, [u8(0x00)])
	}
	mut val := value
	mut bytes := []u8{}
	for val > 0 {
		bytes.prepend(u8(val & 0xFF))
		val = val >> 8
	}
	// Prepend 0x00 if high bit is set (to avoid being interpreted as negative)
	if bytes[0] & 0x80 != 0 {
		bytes.prepend(0x00)
	}
	return der_tag_length_value(0x02, bytes)
}
