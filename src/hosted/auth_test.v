module hosted

// --- DbAuthenticator ---

fn test_db_authenticator_valid_key() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('auth@example.com', 'Auth')!
	result := db.create_api_key(user.id, 'test')!

	authenticator := new_db_authenticator(db)
	auth_result := authenticator.validate(result.raw_key)!
	assert auth_result.user_id == user.id
	assert auth_result.tier == 'free'
	assert auth_result.max_tunnels == 1
}

fn test_db_authenticator_invalid_key() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	authenticator := new_db_authenticator(db)
	if _ := authenticator.validate('vtk_invalid') {
		assert false, 'invalid key should fail'
	}
}

fn test_db_authenticator_pro_tier() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('pro@example.com', 'Pro')!
	db.update_tier(user.id, 'pro')!
	result := db.create_api_key(user.id, 'pro-key')!

	authenticator := new_db_authenticator(db)
	auth_result := authenticator.validate(result.raw_key)!
	assert auth_result.tier == 'pro'
	assert auth_result.max_tunnels == 5
	assert auth_result.max_bw_bytes == 10_737_418_240
}
