module hosted

// --- get_tier_limits ---

fn test_free_tier_limits() {
	limits := get_tier_limits('free')
	assert limits.max_tunnels == 1
	assert limits.max_bw_bytes == 1_073_741_824
	assert limits.max_conn_per_min == 60
	assert limits.custom_subdomain == false
}

fn test_pro_tier_limits() {
	limits := get_tier_limits('pro')
	assert limits.max_tunnels == 5
	assert limits.max_bw_bytes == 10_737_418_240
	assert limits.max_conn_per_min == 300
	assert limits.custom_subdomain == true
}

fn test_self_hosted_tier_limits() {
	limits := get_tier_limits('self-hosted')
	assert limits.max_tunnels == -1
	assert limits.max_bw_bytes == -1
	assert limits.max_conn_per_min == -1
	assert limits.custom_subdomain == true
}

fn test_unknown_tier_defaults_unlimited() {
	limits := get_tier_limits('unknown')
	assert limits.max_tunnels == -1
	assert limits.max_bw_bytes == -1
}

// --- is_unlimited ---

fn test_is_unlimited_negative() {
	assert is_unlimited(-1) == true
}

fn test_is_unlimited_positive() {
	assert is_unlimited(5) == false
}

fn test_is_unlimited_zero() {
	assert is_unlimited(0) == false
}

// --- is_unlimited_bytes ---

fn test_is_unlimited_bytes_negative() {
	assert is_unlimited_bytes(-1) == true
}

fn test_is_unlimited_bytes_positive() {
	assert is_unlimited_bytes(1024) == false
}
