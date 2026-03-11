module hosted

import crypto.rand
import crypto.sha256
import encoding.hex

// ApiKey represents an API key record (without the raw key).
pub struct ApiKey {
pub:
	id         string
	user_id    string
	key_prefix string
	name       string
	created_at string
	last_used  string
	revoked    bool
}

// ApiKeyResult is returned when creating a new API key.
// Contains the raw key (shown once) and the stored record.
pub struct ApiKeyResult {
pub:
	raw_key string
	key     ApiKey
}

// generate_api_key creates a new API key with the "vtk_" prefix.
// Returns the raw key string.
pub fn generate_api_key() !string {
	bytes := rand.read(16)!
	return 'vtk_${hex.encode(bytes)}'
}

// hash_api_key returns the SHA-256 hex digest of an API key.
pub fn hash_api_key(key string) string {
	return sha256.hexhash(key)
}

// key_prefix extracts the display prefix from an API key.
// Returns the first 8 characters (e.g., "vtk_a1b2").
pub fn key_prefix(key string) string {
	if key.len <= 8 {
		return key
	}
	return key[..8]
}

// create_api_key generates a new API key for a user and stores it.
// Returns the raw key (shown once) and the stored record.
pub fn (d &Database) create_api_key(user_id string, name string) !ApiKeyResult {
	raw := generate_api_key()!
	id := generate_uuid()!
	hash := hash_api_key(raw)
	prefix := key_prefix(raw)
	now := now_iso()

	d.conn.exec_param_many('INSERT INTO api_keys (id, user_id, key_hash, key_prefix, name, created_at, revoked) VALUES (?, ?, ?, ?, ?, ?, 0)',
		[id, user_id, hash, prefix, name, now]) or {
		return error('failed to create api key: ${err}')
	}

	return ApiKeyResult{
		raw_key: raw
		key:     ApiKey{
			id:         id
			user_id:    user_id
			key_prefix: prefix
			name:       name
			created_at: now
		}
	}
}

// validate_api_key looks up an API key by its hash and returns the key record.
// Also updates the last_used timestamp.
pub fn (d &Database) validate_api_key(raw_key string) !ApiKey {
	hash := hash_api_key(raw_key)
	rows := d.conn.exec_param_many('SELECT id, user_id, key_prefix, name, created_at, last_used, revoked FROM api_keys WHERE key_hash = ?',
		[hash]) or { return error('failed to validate api key: ${err}') }

	if rows.len == 0 {
		return error('invalid api key')
	}
	row := rows[0]
	vals := row.vals
	revoked := vals[6] == '1'
	if revoked {
		return error('api key has been revoked')
	}

	// Update last_used timestamp
	now := now_iso()
	d.conn.exec_param_many('UPDATE api_keys SET last_used = ? WHERE key_hash = ?', [
		now,
		hash,
	]) or {}

	return ApiKey{
		id:         vals[0]
		user_id:    vals[1]
		key_prefix: vals[2]
		name:       vals[3]
		created_at: vals[4]
		last_used:  now
		revoked:    false
	}
}

// list_api_keys returns all non-revoked API keys for a user.
pub fn (d &Database) list_api_keys(user_id string) ![]ApiKey {
	rows := d.conn.exec_param_many('SELECT id, user_id, key_prefix, name, created_at, last_used, revoked FROM api_keys WHERE user_id = ? AND revoked = 0',
		[user_id]) or { return error('failed to list api keys: ${err}') }

	mut keys := []ApiKey{}
	for row in rows {
		vals := row.vals
		keys << ApiKey{
			id:         vals[0]
			user_id:    vals[1]
			key_prefix: vals[2]
			name:       vals[3]
			created_at: vals[4]
			last_used:  vals[5]
			revoked:    false
		}
	}
	return keys
}

// revoke_api_key marks an API key as revoked.
pub fn (d &Database) revoke_api_key(key_id string) ! {
	d.conn.exec_param_many('UPDATE api_keys SET revoked = 1 WHERE id = ?', [key_id]) or {
		return error('failed to revoke api key: ${err}')
	}
}
