module hosted

// --- generate_api_key ---

fn test_generate_api_key_prefix() {
	key := generate_api_key()!
	assert key.starts_with('vtk_'), 'API key should start with vtk_'
}

fn test_generate_api_key_length() {
	key := generate_api_key()!
	// vtk_ (4 chars) + 32 hex chars = 36
	assert key.len == 36, 'API key should be 36 chars, got ${key.len}'
}

fn test_generate_api_key_uniqueness() {
	k1 := generate_api_key()!
	k2 := generate_api_key()!
	assert k1 != k2, 'API keys should be unique'
}

// --- hash_api_key ---

fn test_hash_api_key_deterministic() {
	h1 := hash_api_key('vtk_abc123')
	h2 := hash_api_key('vtk_abc123')
	assert h1 == h2, 'same key should produce same hash'
}

fn test_hash_api_key_different_inputs() {
	h1 := hash_api_key('vtk_abc123')
	h2 := hash_api_key('vtk_def456')
	assert h1 != h2, 'different keys should produce different hashes'
}

// --- key_prefix ---

fn test_key_prefix_normal() {
	p := key_prefix('vtk_a1b2c3d4e5f6')
	assert p == 'vtk_a1b2', 'prefix should be first 8 chars'
}

fn test_key_prefix_short() {
	p := key_prefix('vtk')
	assert p == 'vtk', 'short key returns full key'
}

// --- create_api_key ---

fn test_create_api_key() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('key@example.com', 'Key Test')!
	result := db.create_api_key(user.id, 'test-key')!
	assert result.raw_key.starts_with('vtk_'), 'raw key should start with vtk_'
	assert result.key.user_id == user.id
	assert result.key.name == 'test-key'
}

// --- validate_api_key ---

fn test_validate_api_key() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('val@example.com', 'Validate')!
	result := db.create_api_key(user.id, 'my-key')!
	key := db.validate_api_key(result.raw_key)!
	assert key.user_id == user.id
	assert key.name == 'my-key'
}

fn test_validate_api_key_invalid() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	if _ := db.validate_api_key('vtk_nonexistent') {
		assert false, 'invalid key should fail'
	}
}

fn test_validate_api_key_revoked() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('rev@example.com', 'Revoke')!
	result := db.create_api_key(user.id, 'to-revoke')!
	db.revoke_api_key(result.key.id)!
	if _ := db.validate_api_key(result.raw_key) {
		assert false, 'revoked key should fail'
	}
}

// --- list_api_keys ---

fn test_list_api_keys() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('list@example.com', 'List')!
	db.create_api_key(user.id, 'key-1')!
	db.create_api_key(user.id, 'key-2')!
	keys := db.list_api_keys(user.id)!
	assert keys.len == 2
}

fn test_list_api_keys_excludes_revoked() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('excl@example.com', 'Exclude')!
	r1 := db.create_api_key(user.id, 'keep')!
	r2 := db.create_api_key(user.id, 'revoke')!
	db.revoke_api_key(r2.key.id)!
	_ = r1
	keys := db.list_api_keys(user.id)!
	assert keys.len == 1
	assert keys[0].name == 'keep'
}

fn test_list_api_keys_empty() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('empty@example.com', 'Empty')!
	keys := db.list_api_keys(user.id)!
	assert keys.len == 0
}
