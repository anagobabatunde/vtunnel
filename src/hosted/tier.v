module hosted

// TierLimits defines the resource limits for a subscription tier.
pub struct TierLimits {
pub:
	max_tunnels      int  // max concurrent tunnels (-1 = unlimited)
	max_bw_bytes     i64  // max bandwidth per month in bytes (-1 = unlimited)
	max_conn_per_min int  // max new connections per minute (-1 = unlimited)
	custom_subdomain bool // whether custom subdomains are allowed
}

// get_tier_limits returns the limits for a given tier name.
pub fn get_tier_limits(tier string) TierLimits {
	return match tier {
		'free' {
			TierLimits{
				max_tunnels:      1
				max_bw_bytes:     1_073_741_824 // 1 GB
				max_conn_per_min: 60
				custom_subdomain: false
			}
		}
		'pro' {
			TierLimits{
				max_tunnels:      5
				max_bw_bytes:     10_737_418_240 // 10 GB
				max_conn_per_min: 300
				custom_subdomain: true
			}
		}
		else {
			// self-hosted or unknown — unlimited
			TierLimits{
				max_tunnels:      -1
				max_bw_bytes:     -1
				max_conn_per_min: -1
				custom_subdomain: true
			}
		}
	}
}

// is_unlimited checks if a limit value means unlimited.
pub fn is_unlimited(limit int) bool {
	return limit < 0
}

// is_unlimited_bytes checks if a bandwidth limit means unlimited.
pub fn is_unlimited_bytes(limit i64) bool {
	return limit < 0
}
