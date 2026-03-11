module hosted

// ReservedSubdomain represents a subdomain reserved by a user.
pub struct ReservedSubdomain {
pub:
	subdomain  string
	user_id    string
	created_at string
}

// reserve_subdomain reserves a subdomain for a user.
pub fn (d &Database) reserve_subdomain(user_id string, subdomain string) ! {
	now := now_iso()
	d.conn.exec_param_many('INSERT INTO reserved_subdomains (subdomain, user_id, created_at) VALUES (?, ?, ?)',
		[subdomain, user_id, now]) or { return error('subdomain already reserved: ${subdomain}') }
}

// release_subdomain removes a subdomain reservation.
pub fn (d &Database) release_subdomain(subdomain string) ! {
	d.conn.exec_param_many('DELETE FROM reserved_subdomains WHERE subdomain = ?', [
		subdomain,
	]) or { return error('failed to release subdomain: ${err}') }
}

// get_user_subdomains returns all subdomains reserved by a user.
pub fn (d &Database) get_user_subdomains(user_id string) ![]ReservedSubdomain {
	rows := d.conn.exec_param_many('SELECT subdomain, user_id, created_at FROM reserved_subdomains WHERE user_id = ?',
		[user_id]) or { return error('failed to get subdomains: ${err}') }

	mut subs := []ReservedSubdomain{}
	for row in rows {
		vals := row.vals
		subs << ReservedSubdomain{
			subdomain:  vals[0]
			user_id:    vals[1]
			created_at: vals[2]
		}
	}
	return subs
}

// is_subdomain_reserved checks if a subdomain is reserved by any user.
pub fn (d &Database) is_subdomain_reserved(subdomain string) !bool {
	rows := d.conn.exec_param_many('SELECT 1 FROM reserved_subdomains WHERE subdomain = ?',
		[subdomain]) or { return error('failed to check subdomain: ${err}') }
	return rows.len > 0
}

// get_subdomain_owner returns the user ID who reserved a subdomain, or empty string.
pub fn (d &Database) get_subdomain_owner(subdomain string) !string {
	rows := d.conn.exec_param_many('SELECT user_id FROM reserved_subdomains WHERE subdomain = ?',
		[subdomain]) or { return error('failed to get subdomain owner: ${err}') }
	if rows.len == 0 {
		return ''
	}
	return rows[0].vals[0]
}
