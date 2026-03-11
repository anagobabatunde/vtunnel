module hosted

// --- reserve_subdomain ---

fn test_reserve_subdomain() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('sub@example.com', 'Sub')!
	db.reserve_subdomain(user.id, 'myapp')!
	reserved := db.is_subdomain_reserved('myapp')!
	assert reserved == true
}

fn test_reserve_subdomain_duplicate() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('dup@example.com', 'Dup')!
	db.reserve_subdomain(user.id, 'taken')!
	if _ := db.reserve_subdomain(user.id, 'taken') {
		assert false, 'duplicate subdomain should fail'
	}
}

// --- release_subdomain ---

fn test_release_subdomain() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('rel@example.com', 'Release')!
	db.reserve_subdomain(user.id, 'temp')!
	db.release_subdomain('temp')!
	reserved := db.is_subdomain_reserved('temp')!
	assert reserved == false
}

// --- get_user_subdomains ---

fn test_get_user_subdomains() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('subs@example.com', 'Subs')!
	db.reserve_subdomain(user.id, 'app1')!
	db.reserve_subdomain(user.id, 'app2')!
	subs := db.get_user_subdomains(user.id)!
	assert subs.len == 2
}

fn test_get_user_subdomains_empty() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('nosub@example.com', 'NoSub')!
	subs := db.get_user_subdomains(user.id)!
	assert subs.len == 0
}

// --- is_subdomain_reserved ---

fn test_is_subdomain_not_reserved() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	reserved := db.is_subdomain_reserved('nope')!
	assert reserved == false
}

// --- get_subdomain_owner ---

fn test_get_subdomain_owner() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('own@example.com', 'Owner')!
	db.reserve_subdomain(user.id, 'owned')!
	owner := db.get_subdomain_owner('owned')!
	assert owner == user.id
}

fn test_get_subdomain_owner_unowned() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	owner := db.get_subdomain_owner('unowned')!
	assert owner == ''
}
