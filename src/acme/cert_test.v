module acme

import os
import time

// --- parse_openssl_date ---

fn test_parse_openssl_date_valid() {
	t := parse_openssl_date('Jan 15 00:00:00 2027 GMT') or {
		assert false, 'parse failed: ${err}'
		return
	}
	assert t.year == 2027
	assert t.month == 1
	assert t.day == 15
	assert t.hour == 0
	assert t.minute == 0
	assert t.second == 0
}

fn test_parse_openssl_date_with_time() {
	t := parse_openssl_date('Dec 31 23:59:59 2025 GMT') or {
		assert false, 'parse failed: ${err}'
		return
	}
	assert t.year == 2025
	assert t.month == 12
	assert t.day == 31
	assert t.hour == 23
	assert t.minute == 59
	assert t.second == 59
}

fn test_parse_openssl_date_all_months() {
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
	for i, m in months {
		t := parse_openssl_date('${m} 01 00:00:00 2026 GMT') or {
			assert false, 'parse failed for ${m}: ${err}'
			return
		}
		assert t.month == i + 1, 'month ${m} should be ${i + 1}'
	}
}

fn test_parse_openssl_date_invalid_format() {
	if _ := parse_openssl_date('invalid') {
		assert false, 'should error on invalid format'
	}
}

fn test_parse_openssl_date_unknown_month() {
	if _ := parse_openssl_date('Xyz 01 00:00:00 2026 GMT') {
		assert false, 'should error on unknown month'
	}
}

// --- month_to_int ---

fn test_month_to_int_valid() {
	assert month_to_int('Jan') or { 0 } == 1
	assert month_to_int('Jun') or { 0 } == 6
	assert month_to_int('Dec') or { 0 } == 12
}

fn test_month_to_int_invalid() {
	if _ := month_to_int('Foo') {
		assert false, 'should error on invalid month'
	}
}

// --- cert_needs_renewal ---

fn test_cert_needs_renewal_expired() {
	info := CertInfo{
		cert_path: '/tmp/test.pem'
		key_path:  '/tmp/test.key'
		domain:    'example.com'
		not_after: time.now().add(-24 * time.hour) // expired yesterday
	}
	assert cert_needs_renewal(info, 30 * 24 * time.hour) == true
}

fn test_cert_needs_renewal_within_window() {
	info := CertInfo{
		cert_path: '/tmp/test.pem'
		key_path:  '/tmp/test.key'
		domain:    'example.com'
		not_after: time.now().add(15 * 24 * time.hour) // expires in 15 days
	}
	// Renew 30 days before expiry → should renew
	assert cert_needs_renewal(info, 30 * 24 * time.hour) == true
}

fn test_cert_needs_renewal_not_needed() {
	info := CertInfo{
		cert_path: '/tmp/test.pem'
		key_path:  '/tmp/test.key'
		domain:    'example.com'
		not_after: time.now().add(90 * 24 * time.hour) // expires in 90 days
	}
	// Renew 30 days before expiry → should NOT renew
	assert cert_needs_renewal(info, 30 * 24 * time.hour) == false
}

// --- save_certificate + save_private_key ---

fn test_save_certificate() {
	path := '/tmp/vtunnel_test_cert_${os.getpid()}.pem'
	defer {
		os.rm(path) or {}
	}
	pem_data := '-----BEGIN CERTIFICATE-----\nMIIBxx...\n-----END CERTIFICATE-----\n'
	save_certificate(path, pem_data) or {
		assert false, 'save cert failed: ${err}'
		return
	}
	content := os.read_file(path) or {
		assert false, 'read failed: ${err}'
		return
	}
	assert content == pem_data
}

fn test_save_private_key() {
	path := '/tmp/vtunnel_test_key_${os.getpid()}.pem'
	defer {
		os.rm(path) or {}
	}
	pem_data := '-----BEGIN EC PRIVATE KEY-----\nMHQC...\n-----END EC PRIVATE KEY-----\n'
	save_private_key(path, pem_data) or {
		assert false, 'save key failed: ${err}'
		return
	}
	content := os.read_file(path) or {
		assert false, 'read failed: ${err}'
		return
	}
	assert content == pem_data
}

// --- load_cert_info ---

fn test_load_cert_info_missing_cert() {
	if _ := load_cert_info('/tmp/nonexistent_cert.pem', '/tmp/nonexistent_key.pem', 'test.com') {
		assert false, 'should error on missing cert file'
	}
}

fn test_load_cert_info_missing_key() {
	cert_path := '/tmp/vtunnel_test_ci_cert_${os.getpid()}.pem'
	os.write_file(cert_path, 'dummy') or {}
	defer {
		os.rm(cert_path) or {}
	}
	if _ := load_cert_info(cert_path, '/tmp/nonexistent_key.pem', 'test.com') {
		assert false, 'should error on missing key file'
	}
}
