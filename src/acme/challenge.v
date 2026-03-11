module acme

// ChallengeStore holds HTTP-01 challenge tokens and their key authorizations.
// Thread-safe via V's `shared` map — safe to read/write from multiple coroutines.
@[heap]
pub struct ChallengeStore {
pub mut:
	tokens shared map[string]string // token -> key_authorization
}

// new_challenge_store creates an empty ChallengeStore.
pub fn new_challenge_store() &ChallengeStore {
	return &ChallengeStore{}
}

// set stores a token → key_authorization mapping for an HTTP-01 challenge.
pub fn (mut s ChallengeStore) set(token string, key_auth string) {
	lock s.tokens {
		s.tokens[token] = key_auth
	}
}

// get retrieves the key authorization for a given challenge token.
// Returns none if the token is not found.
pub fn (s ChallengeStore) get(token string) ?string {
	rlock s.tokens {
		if val := s.tokens[token] {
			return val
		}
	}
	return none
}

// remove deletes a challenge token from the store.
pub fn (mut s ChallengeStore) remove(token string) {
	lock s.tokens {
		s.tokens.delete(token)
	}
}

// key_authorization computes the key authorization string for an HTTP-01 challenge.
// Format: token.thumbprint (per RFC 8555 §8.1).
pub fn key_authorization(token string, thumbprint string) string {
	return '${token}.${thumbprint}'
}
