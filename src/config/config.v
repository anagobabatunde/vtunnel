module config

import os

// ServerConfig holds relay server configuration.
pub struct ServerConfig {
pub mut:
	host           string = '0.0.0.0'
	port           int    = 8080
	http_port      int    = 80
	domain         string = 'localhost'
	token_file     string
	generate_token bool
	tls_cert       string // path to TLS certificate PEM file
	tls_key        string // path to TLS private key PEM file
	ws_port        int    // WebSocket listener port (0 = disabled)
	acme           bool   // enable ACME/Let's Encrypt auto-TLS
	acme_email     string // contact email for ACME account
	acme_dir       string // directory for cert storage (default: ~/.vtunnel/certs)
	acme_staging   bool   // use Let's Encrypt staging environment
	log_level      string = 'info'  // debug, info, warn, error
	log_format     string = 'human' // human, json
}

// ClientConfig holds tunnel client configuration.
pub struct ClientConfig {
pub mut:
	server_addr string = 'localhost:8080'
	local_addr  string = 'localhost:3000'
	subdomain   string = 'myapp'
	auth_token  string
	tls         bool   // connect to server using TLS
	tls_ca      string // path to CA certificate PEM for server verification
	ws          bool   // connect via WebSocket instead of raw TCP
	log_level   string = 'info'  // debug, info, warn, error
	log_format  string = 'human' // human, json
}

// valid_port checks that a port number is in the valid range.
fn valid_port(p int) bool {
	return p >= 1 && p <= 65535
}

// print_server_help prints server CLI usage and exits.
fn print_server_help() {
	println('vtunnel-server — relay server for vtunnel

Usage:
  vtunnel-server [options]

Options:
  --port <port>        control port for tunnel clients (default: 8080)
  --http-port <port>   public HTTP port for visitors (default: 80)
  --host <addr>        bind address (default: 0.0.0.0)
  --domain <domain>    base domain for subdomains (default: localhost)
  --token-file <path>  path to token file (enables auth)
  --generate-token     generate a new token and exit
  --tls-cert <path>    TLS certificate PEM file
  --tls-key <path>     TLS private key PEM file
  --ws-port <port>     WebSocket listener port (0 = disabled)
  --acme               enable ACME auto-TLS via LetsEncrypt
  --acme-email <email> contact email for ACME account
  --acme-dir <path>    cert storage directory (default: ~/.vtunnel/certs)
  --acme-staging       use LE staging environment
  --log-level <level>  log level: debug, info, warn, error (default: info)
  --log-format <fmt>   log format: human, json (default: human)
  --help               show this help message')
}

// print_client_help prints client CLI usage and exits.
fn print_client_help() {
	println('vtunnel-client — tunnel client for vtunnel

Usage:
  vtunnel-client [options]

Options:
  --server <host:port>  server address (default: localhost:8080)
  --local <host:port>   local service address (default: localhost:3000)
  --subdomain <name>    subdomain to register (default: myapp)
  --token <token>       auth token for server
  --tls                 connect using TLS
  --tls-ca <path>       CA certificate PEM for server verification
  --ws                  connect via WebSocket instead of raw TCP
  --log-level <level>   log level: debug, info, warn, error (default: info)
  --log-format <fmt>    log format: human, json (default: human)
  --help                show this help message')
}

// parse_server_args reads os.args into a ServerConfig.
pub fn parse_server_args() ServerConfig {
	mut cfg := ServerConfig{}
	args := os.args[1..]
	mut i := 0
	for i < args.len {
		match args[i] {
			'--help', '-h' {
				print_server_help()
				exit(0)
			}
			'--port' {
				if i + 1 < args.len {
					cfg.port = args[i + 1].int()
					i++
				}
			}
			'--http-port' {
				if i + 1 < args.len {
					cfg.http_port = args[i + 1].int()
					i++
				}
			}
			'--domain' {
				if i + 1 < args.len {
					cfg.domain = args[i + 1]
					i++
				}
			}
			'--token-file' {
				if i + 1 < args.len {
					cfg.token_file = args[i + 1]
					i++
				}
			}
			'--host' {
				if i + 1 < args.len {
					cfg.host = args[i + 1]
					i++
				}
			}
			'--generate-token' {
				cfg.generate_token = true
			}
			'--tls-cert' {
				if i + 1 < args.len {
					cfg.tls_cert = args[i + 1]
					i++
				}
			}
			'--tls-key' {
				if i + 1 < args.len {
					cfg.tls_key = args[i + 1]
					i++
				}
			}
			'--ws-port' {
				if i + 1 < args.len {
					cfg.ws_port = args[i + 1].int()
					i++
				}
			}
			'--acme' {
				cfg.acme = true
			}
			'--acme-email' {
				if i + 1 < args.len {
					cfg.acme_email = args[i + 1]
					i++
				}
			}
			'--acme-dir' {
				if i + 1 < args.len {
					cfg.acme_dir = args[i + 1]
					i++
				}
			}
			'--acme-staging' {
				cfg.acme_staging = true
			}
			'--log-level' {
				if i + 1 < args.len {
					cfg.log_level = args[i + 1]
					i++
				}
			}
			'--log-format' {
				if i + 1 < args.len {
					cfg.log_format = args[i + 1]
					i++
				}
			}
			else {}
		}
		i++
	}
	// Validate port ranges
	if !valid_port(cfg.port) {
		eprintln('invalid --port: ${cfg.port} (must be 1-65535)')
		exit(1)
	}
	if !valid_port(cfg.http_port) {
		eprintln('invalid --http-port: ${cfg.http_port} (must be 1-65535)')
		exit(1)
	}
	if cfg.ws_port != 0 && !valid_port(cfg.ws_port) {
		eprintln('invalid --ws-port: ${cfg.ws_port} (must be 1-65535)')
		exit(1)
	}
	// Warn if only one TLS file provided
	if (cfg.tls_cert.len > 0) != (cfg.tls_key.len > 0) {
		eprintln('both --tls-cert and --tls-key are required for TLS')
		exit(1)
	}
	// Validate ACME options
	if cfg.acme {
		if cfg.tls_cert.len > 0 || cfg.tls_key.len > 0 {
			eprintln('--acme and --tls-cert/--tls-key are mutually exclusive')
			exit(1)
		}
		if cfg.domain == 'localhost' {
			eprintln('--acme requires --domain with a real domain (not localhost)')
			exit(1)
		}
		if cfg.acme_email.len == 0 {
			eprintln('--acme requires --acme-email <email>')
			exit(1)
		}
		// Set default acme directory if not specified
		if cfg.acme_dir.len == 0 {
			home := os.home_dir()
			cfg.acme_dir = os.join_path(home, '.vtunnel', 'certs')
		}
	}
	return cfg
}

// parse_client_args reads os.args into a ClientConfig.
pub fn parse_client_args() ClientConfig {
	mut cfg := ClientConfig{}
	args := os.args[1..]
	mut i := 0
	for i < args.len {
		match args[i] {
			'--help', '-h' {
				print_client_help()
				exit(0)
			}
			'--server' {
				if i + 1 < args.len {
					cfg.server_addr = args[i + 1]
					i++
				}
			}
			'--local' {
				if i + 1 < args.len {
					cfg.local_addr = args[i + 1]
					i++
				}
			}
			'--subdomain' {
				if i + 1 < args.len {
					cfg.subdomain = args[i + 1]
					i++
				}
			}
			'--token' {
				if i + 1 < args.len {
					cfg.auth_token = args[i + 1]
					i++
				}
			}
			'--tls' {
				cfg.tls = true
			}
			'--tls-ca' {
				if i + 1 < args.len {
					cfg.tls_ca = args[i + 1]
					i++
				}
			}
			'--ws' {
				cfg.ws = true
			}
			'--log-level' {
				if i + 1 < args.len {
					cfg.log_level = args[i + 1]
					i++
				}
			}
			'--log-format' {
				if i + 1 < args.len {
					cfg.log_format = args[i + 1]
					i++
				}
			}
			else {}
		}
		i++
	}
	return cfg
}
