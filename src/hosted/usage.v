module hosted

import time

// Usage represents bandwidth and connection counts for a user in a given month.
pub struct Usage {
pub:
	user_id     string
	month       string
	bytes_in    i64
	bytes_out   i64
	connections int
}

// current_month returns the current month in "YYYY-MM" format.
pub fn current_month() string {
	now := time.now()
	return '${now.year}-${now.month:02}'
}

// record_bytes adds inbound/outbound byte counts for the current month.
pub fn (d &Database) record_bytes(user_id string, bytes_in i64, bytes_out i64) ! {
	month := current_month()
	id := generate_uuid()!
	d.conn.exec_param_many('INSERT INTO usage (id, user_id, month, bytes_in, bytes_out, connections)
		VALUES (?, ?, ?, ?, ?, 0)
		ON CONFLICT(user_id, month) DO UPDATE SET
			bytes_in = bytes_in + excluded.bytes_in,
			bytes_out = bytes_out + excluded.bytes_out',
		[id, user_id, month, bytes_in.str(), bytes_out.str()]) or {
		return error('failed to record bytes: ${err}')
	}
}

// record_connection increments the connection count for the current month.
pub fn (d &Database) record_connection(user_id string) ! {
	month := current_month()
	id := generate_uuid()!
	d.conn.exec_param_many('INSERT INTO usage (id, user_id, month, bytes_in, bytes_out, connections)
		VALUES (?, ?, ?, 0, 0, 1)
		ON CONFLICT(user_id, month) DO UPDATE SET
			connections = connections + 1',
		[id, user_id, month]) or { return error('failed to record connection: ${err}') }
}

// get_monthly_usage returns usage for a user in the current month.
pub fn (d &Database) get_monthly_usage(user_id string) !Usage {
	month := current_month()
	return d.get_usage_for_month(user_id, month)
}

// get_usage_for_month returns usage for a specific month.
pub fn (d &Database) get_usage_for_month(user_id string, month string) !Usage {
	rows := d.conn.exec_param_many('SELECT user_id, month, bytes_in, bytes_out, connections FROM usage WHERE user_id = ? AND month = ?',
		[user_id, month]) or { return error('failed to get usage: ${err}') }

	if rows.len == 0 {
		return Usage{
			user_id: user_id
			month:   month
		}
	}

	row := rows[0]
	vals := row.vals
	return Usage{
		user_id:     vals[0]
		month:       vals[1]
		bytes_in:    vals[2].i64()
		bytes_out:   vals[3].i64()
		connections: vals[4].int()
	}
}

// check_bandwidth_limit checks if a user has exceeded their monthly bandwidth limit.
// Returns true if within limits, false if exceeded.
pub fn (d &Database) check_bandwidth_limit(user_id string, max_bytes i64) !bool {
	if is_unlimited_bytes(max_bytes) {
		return true
	}
	usage := d.get_monthly_usage(user_id)!
	total := usage.bytes_in + usage.bytes_out
	return total < max_bytes
}
