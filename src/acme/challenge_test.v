module acme

// --- new_challenge_store ---

fn test_new_challenge_store_creates_empty_store() {
	s := new_challenge_store()
	assert s.get('nonexistent') == none
}

// --- set + get ---

fn test_set_and_get_single_token() {
	mut s := new_challenge_store()
	s.set('abc123', 'abc123.thumbprint_value')
	val := s.get('abc123') or {
		assert false, 'expected token to exist'
		return
	}
	assert val == 'abc123.thumbprint_value'
}

fn test_set_and_get_multiple_tokens() {
	mut s := new_challenge_store()
	s.set('token1', 'auth1')
	s.set('token2', 'auth2')
	s.set('token3', 'auth3')

	assert s.get('token1') or { '' } == 'auth1'
	assert s.get('token2') or { '' } == 'auth2'
	assert s.get('token3') or { '' } == 'auth3'
}

fn test_get_nonexistent_returns_none() {
	s := new_challenge_store()
	assert s.get('missing') == none
}

fn test_set_overwrites_existing_token() {
	mut s := new_challenge_store()
	s.set('tok', 'old_value')
	s.set('tok', 'new_value')
	val := s.get('tok') or {
		assert false, 'expected token to exist'
		return
	}
	assert val == 'new_value'
}

// --- remove ---

fn test_remove_existing_token() {
	mut s := new_challenge_store()
	s.set('tok', 'auth')
	s.remove('tok')
	assert s.get('tok') == none
}

fn test_remove_nonexistent_token_is_noop() {
	mut s := new_challenge_store()
	s.remove('nonexistent') // should not panic
	assert s.get('nonexistent') == none
}

fn test_remove_does_not_affect_other_tokens() {
	mut s := new_challenge_store()
	s.set('keep', 'keep_auth')
	s.set('remove_me', 'remove_auth')
	s.remove('remove_me')
	assert s.get('keep') or { '' } == 'keep_auth'
	assert s.get('remove_me') == none
}

// --- key_authorization ---

fn test_key_authorization_format() {
	result := key_authorization('challenge_token', 'account_thumbprint')
	assert result == 'challenge_token.account_thumbprint'
}

fn test_key_authorization_empty_token() {
	result := key_authorization('', 'thumb')
	assert result == '.thumb'
}

fn test_key_authorization_empty_thumbprint() {
	result := key_authorization('tok', '')
	assert result == 'tok.'
}

fn test_key_authorization_both_empty() {
	result := key_authorization('', '')
	assert result == '.'
}

// --- edge cases ---

fn test_set_empty_token() {
	mut s := new_challenge_store()
	s.set('', 'auth_for_empty')
	val := s.get('') or {
		assert false, 'expected empty token key to exist'
		return
	}
	assert val == 'auth_for_empty'
}

fn test_set_empty_key_auth() {
	mut s := new_challenge_store()
	s.set('tok', '')
	val := s.get('tok') or {
		assert false, 'expected token to exist'
		return
	}
	assert val == ''
}
