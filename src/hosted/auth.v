module hosted

import src.auth

// DbAuthenticator validates API keys against the database.
// Implements the auth.Authenticator interface for hosted mode.
@[heap]
pub struct DbAuthenticator {
	database &Database
}

// new_db_authenticator creates an authenticator backed by the database.
pub fn new_db_authenticator(database &Database) &DbAuthenticator {
	return &DbAuthenticator{
		database: database
	}
}

// requires_auth returns true because hosted mode requires API key authentication.
pub fn (a &DbAuthenticator) requires_auth() bool {
	return true
}

// validate checks an API key against the database and returns the user's auth context.
pub fn (a &DbAuthenticator) validate(token string) !auth.AuthResult {
	key := a.database.validate_api_key(token)!
	user := a.database.get_user(key.user_id)!
	limits := get_tier_limits(user.tier)
	return auth.AuthResult{
		user_id:      user.id
		tier:         user.tier
		max_tunnels:  limits.max_tunnels
		max_bw_bytes: limits.max_bw_bytes
	}
}
