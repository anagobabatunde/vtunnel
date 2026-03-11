module config

// --- ServerConfig defaults ---

fn test_server_config_defaults() {
	cfg := ServerConfig{}
	assert cfg.host == '0.0.0.0'
	assert cfg.port == 8080
	assert cfg.http_port == 80
	assert cfg.domain == 'localhost'
	assert cfg.token_file == ''
	assert cfg.generate_token == false
	assert cfg.tls_cert == ''
	assert cfg.tls_key == ''
	assert cfg.ws_port == 0
	assert cfg.acme == false
	assert cfg.acme_email == ''
	assert cfg.acme_dir == ''
	assert cfg.acme_staging == false
	assert cfg.log_level == 'info'
	assert cfg.log_format == 'human'
}

// --- ServerConfig ACME field assignment ---

fn test_server_config_acme_fields() {
	cfg := ServerConfig{
		acme:         true
		acme_email:   'admin@example.com'
		acme_dir:     '/etc/vtunnel/certs'
		acme_staging: true
	}
	assert cfg.acme == true
	assert cfg.acme_email == 'admin@example.com'
	assert cfg.acme_dir == '/etc/vtunnel/certs'
	assert cfg.acme_staging == true
}

// --- ClientConfig defaults ---

fn test_client_config_defaults() {
	cfg := ClientConfig{}
	assert cfg.server_addr == 'localhost:8080'
	assert cfg.local_addr == 'localhost:3000'
	assert cfg.subdomain == 'myapp'
	assert cfg.auth_token == ''
	assert cfg.tls == false
	assert cfg.tls_ca == ''
	assert cfg.ws == false
	assert cfg.log_level == 'info'
	assert cfg.log_format == 'human'
}

// --- ServerConfig field assignment ---

fn test_server_config_field_assignment() {
	cfg := ServerConfig{
		host:       '127.0.0.1'
		port:       9090
		http_port:  8081
		domain:     'example.com'
		token_file: '/tmp/tokens.txt'
		tls_cert:   '/tmp/cert.pem'
		tls_key:    '/tmp/key.pem'
	}
	assert cfg.host == '127.0.0.1'
	assert cfg.port == 9090
	assert cfg.http_port == 8081
	assert cfg.domain == 'example.com'
	assert cfg.token_file == '/tmp/tokens.txt'
	assert cfg.tls_cert == '/tmp/cert.pem'
	assert cfg.tls_key == '/tmp/key.pem'
	assert cfg.ws_port == 0
}

// --- ServerConfig ws_port field assignment ---

fn test_server_config_ws_port() {
	cfg := ServerConfig{
		ws_port: 8082
	}
	assert cfg.ws_port == 8082
}

// --- ClientConfig field assignment ---

fn test_client_config_field_assignment() {
	cfg := ClientConfig{
		server_addr: 'example.com:443'
		local_addr:  'localhost:5173'
		subdomain:   'frontend'
		auth_token:  'secret123'
		tls:         true
		tls_ca:      '/tmp/ca.pem'
	}
	assert cfg.server_addr == 'example.com:443'
	assert cfg.local_addr == 'localhost:5173'
	assert cfg.subdomain == 'frontend'
	assert cfg.auth_token == 'secret123'
	assert cfg.tls == true
	assert cfg.tls_ca == '/tmp/ca.pem'
	assert cfg.ws == false
}

// --- ClientConfig ws flag ---

fn test_client_config_ws_flag() {
	cfg := ClientConfig{
		ws: true
	}
	assert cfg.ws == true
}

// --- ServerConfig generate_token flag ---

fn test_server_config_generate_token_flag() {
	mut cfg := ServerConfig{}
	cfg.generate_token = true
	assert cfg.generate_token == true
}

// --- valid_port ---

fn test_valid_port_normal() {
	assert valid_port(80) == true
	assert valid_port(443) == true
	assert valid_port(8080) == true
}

fn test_valid_port_boundaries() {
	assert valid_port(1) == true
	assert valid_port(65535) == true
}

fn test_valid_port_invalid() {
	assert valid_port(0) == false
	assert valid_port(-1) == false
	assert valid_port(65536) == false
	assert valid_port(100000) == false
}

// --- Command enum ---

fn test_command_enum_values() {
	assert Command.http != Command.tcp
	assert Command.server != Command.http
	assert Command.token != Command.server
	assert Command.help != Command.token
}

// --- TokenConfig defaults ---

fn test_token_config_defaults() {
	cfg := TokenConfig{}
	assert cfg.action == ''
	assert cfg.token_file == ''
}

fn test_token_config_field_assignment() {
	cfg := TokenConfig{
		action:     'generate'
		token_file: '/tmp/tokens.txt'
	}
	assert cfg.action == 'generate'
	assert cfg.token_file == '/tmp/tokens.txt'
}

// --- Log config fields ---

fn test_server_config_log_fields() {
	cfg := ServerConfig{
		log_level:  'debug'
		log_format: 'json'
	}
	assert cfg.log_level == 'debug'
	assert cfg.log_format == 'json'
}

fn test_client_config_log_fields() {
	cfg := ClientConfig{
		log_level:  'warn'
		log_format: 'json'
	}
	assert cfg.log_level == 'warn'
	assert cfg.log_format == 'json'
}
