module acme

import crypto.ecdsa
import encoding.base64
import os

// generate_account_key creates a new ECDSA P-256 key pair for ACME account operations.
pub fn generate_account_key() !ecdsa.PrivateKey {
	_, privkey := ecdsa.generate_key()!
	return privkey
}

// save_account_key writes an ECDSA private key seed to a file (base64-encoded).
// The seed is the raw private key bytes (32 bytes for P-256), base64-encoded for safe storage.
pub fn save_account_key(path string, privkey ecdsa.PrivateKey) ! {
	seed := privkey.bytes()!
	encoded := base64.encode(seed)
	os.write_file(path, encoded)!
}

// load_account_key reads an ECDSA private key seed from a file and reconstructs the key.
pub fn load_account_key(path string) !ecdsa.PrivateKey {
	content := os.read_file(path)!
	seed := base64.decode(content.trim_space())
	return ecdsa.new_key_from_seed(seed)!
}

// save_account_kid writes the ACME account URL (kid) to a file.
pub fn save_account_kid(path string, kid string) ! {
	os.write_file(path, kid)!
}

// load_account_kid reads the ACME account URL (kid) from a file.
pub fn load_account_kid(path string) !string {
	content := os.read_file(path)!
	return content.trim_space()
}

// ensure_dir creates a directory and all parent directories if they don't exist.
pub fn ensure_dir(path string) ! {
	if !os.exists(path) {
		os.mkdir_all(path)!
	}
}
