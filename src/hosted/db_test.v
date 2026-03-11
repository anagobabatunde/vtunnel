module hosted

// --- open_database ---

fn test_open_database_memory() {
	mut database := open_database(':memory:')!
	defer {
		database.close()
	}
	// Should create tables without error
	assert true
}

fn test_open_database_migrate_idempotent() {
	mut database := open_database(':memory:')!
	defer {
		database.close()
	}
	// Running migrate again should not error
	database.migrate()!
	assert true
}

// --- now_iso ---

fn test_now_iso_format() {
	ts := now_iso()
	assert ts.len > 0, 'timestamp should not be empty'
	assert ts.contains('T'), 'should be ISO 8601 format'
}
