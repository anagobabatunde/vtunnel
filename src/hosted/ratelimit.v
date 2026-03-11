module hosted

import time

// RateLimiter tracks connection rates per user using a sliding window.
@[heap]
pub struct RateLimiter {
mut:
	windows shared map[string][]i64
}

// new_rate_limiter creates a new rate limiter.
pub fn new_rate_limiter() &RateLimiter {
	return &RateLimiter{}
}

// allow checks if a user is within their rate limit (max_per_min connections per minute).
// Returns true if allowed, false if rate limit exceeded.
// If max_per_min is -1 (unlimited), always returns true.
pub fn (mut rl RateLimiter) allow(user_id string, max_per_min int) bool {
	if is_unlimited(max_per_min) {
		return true
	}

	now := time.now().unix()
	window_start := now - 60

	lock rl.windows {
		mut timestamps := rl.windows[user_id] or { []i64{} }
		// Remove timestamps older than 1 minute
		mut cleaned := []i64{}
		for ts in timestamps {
			if ts > window_start {
				cleaned << ts
			}
		}
		// Check if within limit
		if cleaned.len >= max_per_min {
			rl.windows[user_id] = cleaned
			return false
		}
		// Add current timestamp
		cleaned << now
		rl.windows[user_id] = cleaned
		return true
	}
	return false
}

// reset clears all rate limit data. Used in tests.
pub fn (mut rl RateLimiter) reset() {
	lock rl.windows {
		rl.windows = map[string][]i64{}
	}
}
