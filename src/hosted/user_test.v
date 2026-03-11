module hosted

// --- generate_uuid ---

fn test_generate_uuid_length() {
	id := generate_uuid()!
	assert id.len == 32, 'UUID should be 32 hex chars'
}

fn test_generate_uuid_uniqueness() {
	id1 := generate_uuid()!
	id2 := generate_uuid()!
	assert id1 != id2, 'UUIDs should be unique'
}

// --- create_user ---

fn test_create_user() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('test@example.com', 'Test User')!
	assert user.email == 'test@example.com'
	assert user.name == 'Test User'
	assert user.tier == 'free'
	assert user.id.len == 32
}

fn test_create_user_duplicate_email() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	db.create_user('dupe@example.com', 'First')!
	if _ := db.create_user('dupe@example.com', 'Second') {
		assert false, 'duplicate email should fail'
	}
}

// --- get_user ---

fn test_get_user() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	created := db.create_user('get@example.com', 'Get Test')!
	found := db.get_user(created.id)!
	assert found.email == 'get@example.com'
	assert found.name == 'Get Test'
	assert found.id == created.id
}

fn test_get_user_not_found() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	if _ := db.get_user('nonexistent') {
		assert false, 'should error for missing user'
	}
}

// --- get_user_by_email ---

fn test_get_user_by_email() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	created := db.create_user('email@example.com', 'Email Test')!
	found := db.get_user_by_email('email@example.com')!
	assert found.id == created.id
	assert found.name == 'Email Test'
}

fn test_get_user_by_email_not_found() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	if _ := db.get_user_by_email('nobody@example.com') {
		assert false, 'should error for missing email'
	}
}

// --- update_tier ---

fn test_update_tier() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('tier@example.com', 'Tier')!
	assert user.tier == 'free'
	db.update_tier(user.id, 'pro')!
	updated := db.get_user(user.id)!
	assert updated.tier == 'pro'
}

// --- delete_user ---

fn test_delete_user() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('del@example.com', 'Delete Me')!
	db.delete_user(user.id)!
	if _ := db.get_user(user.id) {
		assert false, 'user should be deleted'
	}
}
