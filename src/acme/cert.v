module acme

import os
import time

// CertInfo holds paths and metadata for a TLS certificate.
pub struct CertInfo {
pub:
	cert_path string    // path to the fullchain PEM file
	key_path  string    // path to the domain private key PEM file
	domain    string    // domain name the certificate covers
	not_after time.Time // certificate expiry time
}

// save_certificate writes a PEM-encoded certificate chain to disk.
pub fn save_certificate(path string, pem_data string) ! {
	os.write_file(path, pem_data)!
}

// save_private_key writes a PEM-encoded private key to disk.
pub fn save_private_key(path string, pem_data string) ! {
	os.write_file(path, pem_data)!
}

// load_cert_info loads certificate metadata from existing cert and key files.
// Parses the Not After date from the PEM certificate to determine expiry.
pub fn load_cert_info(cert_path string, key_path string, domain string) !CertInfo {
	if !os.exists(cert_path) {
		return error('certificate file not found: ${cert_path}')
	}
	if !os.exists(key_path) {
		return error('key file not found: ${key_path}')
	}
	pem_data := os.read_file(cert_path)!
	not_after := parse_not_after_from_pem(pem_data)!
	return CertInfo{
		cert_path: cert_path
		key_path:  key_path
		domain:    domain
		not_after: not_after
	}
}

// cert_needs_renewal returns true if the certificate expires within renew_before duration.
pub fn cert_needs_renewal(info CertInfo, renew_before time.Duration) bool {
	renewal_deadline := info.not_after.add(-renew_before)
	return time.now().unix() >= renewal_deadline.unix()
}

// parse_not_after_from_pem extracts the Not After date from a PEM certificate.
// Uses openssl x509 command to parse the certificate, since V's stdlib doesn't
// have a native X.509 parser.
fn parse_not_after_from_pem(pem_data string) !time.Time {
	// Write PEM to temp file, run openssl x509 -enddate, parse output
	tmp_path := '/tmp/vtunnel_cert_check_${os.getpid()}.pem'
	os.write_file(tmp_path, pem_data)!
	defer {
		os.rm(tmp_path) or {}
	}

	result := os.execute('openssl x509 -enddate -noout -in ${tmp_path}')
	if result.exit_code != 0 {
		return error('openssl x509 failed: ${result.output}')
	}

	// Output format: "notAfter=Mon DD HH:MM:SS YYYY GMT"
	// e.g., "notAfter=Jan 15 00:00:00 2027 GMT"
	line := result.output.trim_space()
	date_str := line.all_after('=').trim_space()
	return parse_openssl_date(date_str)
}

// parse_openssl_date parses a date string in OpenSSL's format.
// Format: "Mon DD HH:MM:SS YYYY GMT" (e.g., "Jan 15 00:00:00 2027 GMT")
fn parse_openssl_date(s string) !time.Time {
	parts := s.split(' ').filter(it.len > 0)
	if parts.len < 5 {
		return error('invalid date format: ${s}')
	}

	month_str := parts[0]
	day := parts[1].int()
	time_parts := parts[2].split(':')
	year := parts[3].int()

	if time_parts.len < 3 {
		return error('invalid time format: ${parts[2]}')
	}

	hour := time_parts[0].int()
	minute := time_parts[1].int()
	second := time_parts[2].int()

	month := month_to_int(month_str)!

	return time.Time{
		year:   year
		month:  month
		day:    day
		hour:   hour
		minute: minute
		second: second
	}
}

// month_to_int converts a 3-letter month abbreviation to its integer value.
fn month_to_int(s string) !int {
	return match s {
		'Jan' { 1 }
		'Feb' { 2 }
		'Mar' { 3 }
		'Apr' { 4 }
		'May' { 5 }
		'Jun' { 6 }
		'Jul' { 7 }
		'Aug' { 8 }
		'Sep' { 9 }
		'Oct' { 10 }
		'Nov' { 11 }
		'Dec' { 12 }
		else { error('unknown month: ${s}') }
	}
}
