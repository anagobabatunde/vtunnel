module hosted

// --- current_month ---

fn test_current_month_format() {
	month := current_month()
	assert month.len >= 6, 'month should be at least 6 chars (YYYY-MM)'
	assert month.contains('-'), 'should contain a dash'
}

// --- record_bytes ---

fn test_record_bytes() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('usage@example.com', 'Usage')!
	db.record_bytes(user.id, 1024, 2048)!
	usage := db.get_monthly_usage(user.id)!
	assert usage.bytes_in == 1024
	assert usage.bytes_out == 2048
}

fn test_record_bytes_accumulates() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('accum@example.com', 'Accum')!
	db.record_bytes(user.id, 100, 200)!
	db.record_bytes(user.id, 300, 400)!
	usage := db.get_monthly_usage(user.id)!
	assert usage.bytes_in == 400
	assert usage.bytes_out == 600
}

// --- record_connection ---

fn test_record_connection() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('conn@example.com', 'Conn')!
	db.record_connection(user.id)!
	db.record_connection(user.id)!
	usage := db.get_monthly_usage(user.id)!
	assert usage.connections == 2
}

// --- get_monthly_usage ---

fn test_get_monthly_usage_empty() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('nousage@example.com', 'NoUsage')!
	usage := db.get_monthly_usage(user.id)!
	assert usage.bytes_in == 0
	assert usage.bytes_out == 0
	assert usage.connections == 0
}

// --- check_bandwidth_limit ---

fn test_check_bandwidth_within_limit() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('limit@example.com', 'Limit')!
	db.record_bytes(user.id, 500, 500)!
	within := db.check_bandwidth_limit(user.id, 2000)!
	assert within == true
}

fn test_check_bandwidth_exceeded() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('over@example.com', 'Over')!
	db.record_bytes(user.id, 1000, 1000)!
	within := db.check_bandwidth_limit(user.id, 1500)!
	assert within == false
}

fn test_check_bandwidth_unlimited() {
	mut db := open_database(':memory:')!
	defer {
		db.close()
	}
	user := db.create_user('unlim@example.com', 'Unlim')!
	db.record_bytes(user.id, 999999999, 999999999)!
	within := db.check_bandwidth_limit(user.id, -1)!
	assert within == true
}
