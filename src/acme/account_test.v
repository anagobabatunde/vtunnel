module acme

import os

// --- generate_account_key ---

fn test_generate_account_key() {
	privkey := generate_account_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	// Should be able to get public key from it
	pubkey := privkey.public_key() or {
		assert false, 'public key extraction failed: ${err}'
		return
	}
	pub_bytes := pubkey.bytes() or {
		assert false, 'public key bytes failed: ${err}'
		return
	}
	// P-256 uncompressed point: 04 || x(32) || y(32) = 65 bytes
	assert pub_bytes.len == 65, 'P-256 public key should be 65 bytes'
	assert pub_bytes[0] == 0x04, 'should be uncompressed point'
}

// --- save_account_key + load_account_key roundtrip ---

fn test_save_and_load_account_key() {
	privkey := generate_account_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	path := '/tmp/vtunnel_test_account_${os.getpid()}.key'
	defer {
		os.rm(path) or {}
	}
	save_account_key(path, privkey) or {
		assert false, 'save failed: ${err}'
		return
	}
	assert os.exists(path), 'key file should exist'

	loaded := load_account_key(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	// Verify the keys are the same by comparing raw seed bytes
	orig_bytes := privkey.bytes() or {
		assert false, 'original key bytes failed: ${err}'
		return
	}
	loaded_bytes := loaded.bytes() or {
		assert false, 'loaded key bytes failed: ${err}'
		return
	}
	assert orig_bytes == loaded_bytes, 'roundtripped key should have same seed'
}

fn test_save_account_key_file_content_is_base64() {
	privkey := generate_account_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	path := '/tmp/vtunnel_test_b64_${os.getpid()}.key'
	defer {
		os.rm(path) or {}
	}
	save_account_key(path, privkey) or {
		assert false, 'save failed: ${err}'
		return
	}
	content := os.read_file(path) or {
		assert false, 'read failed: ${err}'
		return
	}
	// Should be valid base64 (no whitespace, only b64 chars)
	for ch in content {
		is_b64 := (ch >= `A` && ch <= `Z`) || (ch >= `a` && ch <= `z`)
			|| (ch >= `0` && ch <= `9`) || ch == `+` || ch == `/` || ch == `=`
		assert is_b64, 'file content should be valid base64'
	}
}

fn test_load_account_key_nonexistent() {
	if _ := load_account_key('/tmp/nonexistent_vtunnel_key_${os.getpid()}') {
		assert false, 'should error on nonexistent file'
	}
}

fn test_loaded_key_can_sign() {
	privkey := generate_account_key() or {
		assert false, 'key generation failed: ${err}'
		return
	}
	path := '/tmp/vtunnel_test_sign_${os.getpid()}.key'
	defer {
		os.rm(path) or {}
	}
	save_account_key(path, privkey) or {
		assert false, 'save failed: ${err}'
		return
	}
	loaded := load_account_key(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	// Loaded key should be able to sign
	sig := loaded.sign('test message'.bytes()) or {
		assert false, 'signing with loaded key failed: ${err}'
		return
	}
	assert sig.len > 0, 'signature should not be empty'
}

// --- save_account_kid + load_account_kid ---

fn test_save_and_load_account_kid() {
	path := '/tmp/vtunnel_test_kid_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	kid := 'https://acme.example/acct/12345'
	save_account_kid(path, kid) or {
		assert false, 'save kid failed: ${err}'
		return
	}
	loaded := load_account_kid(path) or {
		assert false, 'load kid failed: ${err}'
		return
	}
	assert loaded == kid
}

fn test_load_account_kid_trims_whitespace() {
	path := '/tmp/vtunnel_test_kid_ws_${os.getpid()}.txt'
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, '  https://acme.example/acct/1  \n') or {
		assert false, 'write failed: ${err}'
		return
	}
	loaded := load_account_kid(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert loaded == 'https://acme.example/acct/1'
}

// --- ensure_dir ---

fn test_ensure_dir_creates_directory() {
	path := '/tmp/vtunnel_test_dir_${os.getpid()}'
	defer {
		os.rmdir(path) or {}
	}
	ensure_dir(path) or {
		assert false, 'ensure_dir failed: ${err}'
		return
	}
	assert os.is_dir(path)
}

fn test_ensure_dir_nested() {
	path := '/tmp/vtunnel_test_dir_${os.getpid()}/nested/deep'
	defer {
		os.rmdir_all('/tmp/vtunnel_test_dir_${os.getpid()}') or {}
	}
	ensure_dir(path) or {
		assert false, 'ensure_dir nested failed: ${err}'
		return
	}
	assert os.is_dir(path)
}

fn test_ensure_dir_existing_is_noop() {
	path := '/tmp/vtunnel_test_dir_exist_${os.getpid()}'
	os.mkdir(path) or {}
	defer {
		os.rmdir(path) or {}
	}
	ensure_dir(path) or {
		assert false, 'ensure_dir on existing dir failed: ${err}'
		return
	}
	assert os.is_dir(path)
}
