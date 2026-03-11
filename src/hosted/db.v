module hosted

import db.sqlite
import os
import time

// Database wraps a SQLite connection for the hosted mode.
@[heap]
pub struct Database {
pub mut:
	conn sqlite.DB
}

// open_database opens or creates a SQLite database at the given path.
// Use ":memory:" for testing.
pub fn open_database(path string) !&Database {
	if path != ':memory:' {
		dir := os.dir(path)
		if dir.len > 0 && !os.exists(dir) {
			os.mkdir_all(dir)!
		}
	}
	conn := sqlite.connect(path) or { return error('failed to open database: ${err}') }
	mut database := &Database{
		conn: conn
	}
	database.enable_wal()!
	database.migrate()!
	return database
}

// enable_wal enables Write-Ahead Logging for better concurrent performance.
fn (mut d Database) enable_wal() ! {
	d.conn.exec('PRAGMA journal_mode=WAL') or { return error('failed to set WAL mode: ${err}') }
	d.conn.exec('PRAGMA foreign_keys=ON') or {
		return error('failed to enable foreign keys: ${err}')
	}
}

// migrate runs all database schema migrations.
pub fn (mut d Database) migrate() ! {
	d.conn.exec('CREATE TABLE IF NOT EXISTS users (
		id         TEXT PRIMARY KEY,
		email      TEXT UNIQUE NOT NULL,
		name       TEXT NOT NULL DEFAULT "",
		tier       TEXT NOT NULL DEFAULT "free",
		created_at TEXT NOT NULL,
		updated_at TEXT NOT NULL
	)') or {
		return error('failed to create users table: ${err}')
	}

	d.conn.exec('CREATE TABLE IF NOT EXISTS api_keys (
		id         TEXT PRIMARY KEY,
		user_id    TEXT NOT NULL REFERENCES users(id),
		key_hash   TEXT NOT NULL,
		key_prefix TEXT NOT NULL,
		name       TEXT NOT NULL DEFAULT "default",
		created_at TEXT NOT NULL,
		last_used  TEXT,
		revoked    INTEGER NOT NULL DEFAULT 0
	)') or {
		return error('failed to create api_keys table: ${err}')
	}

	d.conn.exec('CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash)') or {
		return error('failed to create api_keys hash index: ${err}')
	}
	d.conn.exec('CREATE INDEX IF NOT EXISTS idx_api_keys_user ON api_keys(user_id)') or {
		return error('failed to create api_keys user index: ${err}')
	}

	d.conn.exec('CREATE TABLE IF NOT EXISTS reserved_subdomains (
		subdomain  TEXT PRIMARY KEY,
		user_id    TEXT NOT NULL REFERENCES users(id),
		created_at TEXT NOT NULL
	)') or {
		return error('failed to create reserved_subdomains table: ${err}')
	}

	d.conn.exec('CREATE INDEX IF NOT EXISTS idx_reserved_user ON reserved_subdomains(user_id)') or {
		return error('failed to create reserved_subdomains user index: ${err}')
	}

	d.conn.exec('CREATE TABLE IF NOT EXISTS usage (
		id          TEXT PRIMARY KEY,
		user_id     TEXT NOT NULL,
		month       TEXT NOT NULL,
		bytes_in    INTEGER NOT NULL DEFAULT 0,
		bytes_out   INTEGER NOT NULL DEFAULT 0,
		connections INTEGER NOT NULL DEFAULT 0,
		UNIQUE(user_id, month)
	)') or {
		return error('failed to create usage table: ${err}')
	}

	d.conn.exec('CREATE INDEX IF NOT EXISTS idx_usage_user_month ON usage(user_id, month)') or {
		return error('failed to create usage index: ${err}')
	}
}

// close closes the database connection.
pub fn (mut d Database) close() {
	d.conn.close() or {}
}

// now_iso returns the current time as an ISO 8601 string.
pub fn now_iso() string {
	return time.now().format_rfc3339()
}
