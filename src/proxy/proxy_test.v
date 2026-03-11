module proxy

import net
import src.tunnel
import src.transport

// --- Registry ---

fn new_test_tunnel() &tunnel.Tunnel {
	t := transport.new_tcp(net.TcpConn{})
	return tunnel.new(t)
}

fn test_registry_register_and_get() {
	mut reg := new_registry()
	tun := new_test_tunnel()
	reg.register('myapp', tun)

	result := reg.get('myapp') or {
		assert false, 'should find registered tunnel'
		return
	}
	// Verify we got back a tunnel (pointer comparison)
	assert voidptr(result) == voidptr(tun)
}

fn test_registry_is_registered_true() {
	mut reg := new_registry()
	tun := new_test_tunnel()
	reg.register('myapp', tun)
	assert reg.is_registered('myapp') == true
}

fn test_registry_is_registered_false() {
	mut reg := new_registry()
	assert reg.is_registered('nonexistent') == false
}

fn test_registry_unregister() {
	mut reg := new_registry()
	tun := new_test_tunnel()
	reg.register('myapp', tun)
	assert reg.is_registered('myapp') == true

	reg.unregister('myapp')
	assert reg.is_registered('myapp') == false
}

fn test_registry_unregister_nonexistent() {
	mut reg := new_registry()
	// Should not panic
	reg.unregister('nonexistent')
}

fn test_registry_get_nonexistent_returns_none() {
	mut reg := new_registry()
	result := reg.get('nonexistent')
	assert result == none
}

fn test_registry_multiple_subdomains() {
	mut reg := new_registry()
	tun1 := new_test_tunnel()
	tun2 := new_test_tunnel()
	reg.register('app1', tun1)
	reg.register('app2', tun2)

	assert reg.is_registered('app1') == true
	assert reg.is_registered('app2') == true
	assert reg.is_registered('app3') == false

	// Verify they return distinct tunnels
	r1 := reg.get('app1') or { return }
	r2 := reg.get('app2') or { return }
	assert voidptr(r1) != voidptr(r2)
}

fn test_registry_register_overwrites() {
	mut reg := new_registry()
	tun1 := new_test_tunnel()
	tun2 := new_test_tunnel()
	reg.register('myapp', tun1)
	reg.register('myapp', tun2)

	result := reg.get('myapp') or { return }
	assert voidptr(result) == voidptr(tun2)
}

// --- extract_host ---

fn test_extract_host_standard() {
	req := 'GET / HTTP/1.1\r\nHost: myapp.example.com\r\nAccept: */*\r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'myapp.example.com'
}

fn test_extract_host_with_port() {
	req := 'GET / HTTP/1.1\r\nHost: myapp.localhost:8081\r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'myapp.localhost:8081'
}

fn test_extract_host_case_insensitive() {
	req := 'GET / HTTP/1.1\r\nHOST: UPPER.example.com\r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	// Original case preserved in return value
	assert host == 'UPPER.example.com'
}

fn test_extract_host_mixed_case() {
	req := 'GET / HTTP/1.1\r\nhOsT: Mixed.Example.COM\r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'Mixed.Example.COM'
}

fn test_extract_host_lf_only_line_endings() {
	req := 'GET / HTTP/1.1\nHost: lf-only.example.com\n\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'lf-only.example.com'
}

fn test_extract_host_extra_whitespace() {
	req := 'GET / HTTP/1.1\r\nHost:   spaces.example.com   \r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'spaces.example.com'
}

fn test_extract_host_missing_returns_none() {
	req := 'GET / HTTP/1.1\r\nAccept: */*\r\n\r\n'
	result := extract_host(req.bytes())
	assert result == none
}

fn test_extract_host_empty_buffer() {
	result := extract_host([])
	assert result == none
}

fn test_extract_host_among_many_headers() {
	req := 'GET /path HTTP/1.1\r\nAccept: text/html\r\nUser-Agent: test\r\nHost: deep.example.com\r\nConnection: close\r\n\r\n'
	host := extract_host(req.bytes()) or { '' }
	assert host == 'deep.example.com'
}

// --- subdomain_from_host ---

fn test_subdomain_simple() {
	assert subdomain_from_host('myapp.example.com') == 'myapp'
}

fn test_subdomain_with_port() {
	assert subdomain_from_host('myapp.localhost:8081') == 'myapp'
}

fn test_subdomain_bare_hostname() {
	assert subdomain_from_host('localhost') == 'localhost'
}

fn test_subdomain_bare_hostname_with_port() {
	assert subdomain_from_host('localhost:8080') == 'localhost'
}

fn test_subdomain_deep_domain() {
	// First label is always the subdomain
	assert subdomain_from_host('app.sub.example.com') == 'app'
}

fn test_subdomain_ip_address() {
	assert subdomain_from_host('127.0.0.1:8080') == '127'
}

fn test_subdomain_empty_string() {
	assert subdomain_from_host('') == ''
}

// --- extract_path ---

fn test_extract_path_get() {
	req := 'GET /foo/bar HTTP/1.1\r\nHost: example.com\r\n\r\n'
	assert extract_path(req.bytes()) == '/foo/bar'
}

fn test_extract_path_acme_challenge() {
	req := 'GET /.well-known/acme-challenge/test-token HTTP/1.1\r\nHost: example.com\r\n\r\n'
	assert extract_path(req.bytes()) == '/.well-known/acme-challenge/test-token'
}

fn test_extract_path_root() {
	req := 'GET / HTTP/1.1\r\nHost: example.com\r\n\r\n'
	assert extract_path(req.bytes()) == '/'
}

fn test_extract_path_post() {
	req := 'POST /api/data HTTP/1.1\r\nHost: example.com\r\n\r\n'
	assert extract_path(req.bytes()) == '/api/data'
}

fn test_extract_path_empty_returns_slash() {
	assert extract_path([]) == '/'
}
