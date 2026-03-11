module hosted

import crypto.rand
import encoding.hex

// User represents a registered user.
pub struct User {
pub:
	id         string
	email      string
	name       string
	tier       string
	created_at string
	updated_at string
}

// generate_uuid creates a random UUID v4 string.
pub fn generate_uuid() !string {
	bytes := rand.read(16)!
	return hex.encode(bytes)
}

// create_user inserts a new user and returns the User.
pub fn (d &Database) create_user(email string, name string) !User {
	id := generate_uuid()!
	now := now_iso()
	d.conn.exec_param_many('INSERT INTO users (id, email, name, tier, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
		[id, email, name, 'free', now, now]) or { return error('failed to create user: ${err}') }
	return User{
		id:         id
		email:      email
		name:       name
		tier:       'free'
		created_at: now
		updated_at: now
	}
}

// get_user retrieves a user by ID.
pub fn (d &Database) get_user(id string) !User {
	rows := d.conn.exec_param_many('SELECT id, email, name, tier, created_at, updated_at FROM users WHERE id = ?',
		[id]) or { return error('failed to get user: ${err}') }
	if rows.len == 0 {
		return error('user not found: ${id}')
	}
	row := rows[0]
	vals := row.vals
	return User{
		id:         vals[0]
		email:      vals[1]
		name:       vals[2]
		tier:       vals[3]
		created_at: vals[4]
		updated_at: vals[5]
	}
}

// get_user_by_email retrieves a user by email.
pub fn (d &Database) get_user_by_email(email string) !User {
	rows := d.conn.exec_param_many('SELECT id, email, name, tier, created_at, updated_at FROM users WHERE email = ?',
		[email]) or { return error('failed to get user by email: ${err}') }
	if rows.len == 0 {
		return error('user not found: ${email}')
	}
	row := rows[0]
	vals := row.vals
	return User{
		id:         vals[0]
		email:      vals[1]
		name:       vals[2]
		tier:       vals[3]
		created_at: vals[4]
		updated_at: vals[5]
	}
}

// update_tier changes a user's subscription tier.
pub fn (d &Database) update_tier(user_id string, tier string) ! {
	now := now_iso()
	d.conn.exec_param_many('UPDATE users SET tier = ?, updated_at = ? WHERE id = ?', [
		tier,
		now,
		user_id,
	]) or { return error('failed to update tier: ${err}') }
}

// delete_user removes a user by ID. Used in tests.
pub fn (d &Database) delete_user(user_id string) ! {
	d.conn.exec_param_many('DELETE FROM api_keys WHERE user_id = ?', [user_id]) or {
		return error('failed to delete user keys: ${err}')
	}
	d.conn.exec_param_many('DELETE FROM reserved_subdomains WHERE user_id = ?', [
		user_id,
	]) or { return error('failed to delete user subdomains: ${err}') }
	d.conn.exec_param_many('DELETE FROM users WHERE id = ?', [user_id]) or {
		return error('failed to delete user: ${err}')
	}
}
