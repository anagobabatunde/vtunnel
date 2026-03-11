module hosted

// --- RateLimiter ---

fn test_rate_limiter_allows_within_limit() {
	mut rl := new_rate_limiter()
	// Allow 10 per minute
	for _ in 0 .. 10 {
		assert rl.allow('user1', 10) == true
	}
}

fn test_rate_limiter_blocks_over_limit() {
	mut rl := new_rate_limiter()
	// Fill up the limit
	for _ in 0 .. 5 {
		rl.allow('user2', 5)
	}
	// Next one should be blocked
	assert rl.allow('user2', 5) == false
}

fn test_rate_limiter_unlimited() {
	mut rl := new_rate_limiter()
	// -1 means unlimited
	for _ in 0 .. 100 {
		assert rl.allow('unlimited', -1) == true
	}
}

fn test_rate_limiter_independent_users() {
	mut rl := new_rate_limiter()
	// Fill user_a's limit
	for _ in 0 .. 3 {
		rl.allow('user_a', 3)
	}
	// user_b should still be allowed
	assert rl.allow('user_b', 3) == true
}

fn test_rate_limiter_reset() {
	mut rl := new_rate_limiter()
	for _ in 0 .. 5 {
		rl.allow('reset_user', 5)
	}
	assert rl.allow('reset_user', 5) == false
	rl.reset()
	assert rl.allow('reset_user', 5) == true
}
