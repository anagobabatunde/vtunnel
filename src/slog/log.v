module slog

import strings
import time

// Level represents log severity. Ordered from most to least verbose.
pub enum Level {
	debug
	info
	warn
	error
}

// Format controls the output representation.
pub enum Format {
	human // colored, human-readable (default)
	json  // single-line JSON for machine parsing
}

// Logger provides structured, leveled logging.
// Thread-safe: each log call builds a string, then calls println/eprintln (synchronized by V runtime).
@[heap]
pub struct Logger {
pub:
	level     Level  = .info
	format    Format = .human
	component string // e.g. "server", "client", "acme", "control"
}

// LogParams holds optional key-value fields for structured log entries.
@[params]
pub struct LogParams {
pub:
	subdomain   string
	stream_id   int = -1 // -1 means unset
	remote_addr string
	token       string // auto-redacted in output
	err         string
	detail      string
}

// new creates a Logger with the given component name, level, and format.
pub fn new(component string, level Level, format Format) &Logger {
	return &Logger{
		level:     level
		format:    format
		component: component
	}
}

// with_component returns a new Logger with a different component name.
// Inherits level and format from the parent.
pub fn (l &Logger) with_component(component string) &Logger {
	return &Logger{
		level:     l.level
		format:    l.format
		component: component
	}
}

// debug logs a message at debug level.
pub fn (l &Logger) debug(msg string, params LogParams) {
	if int(l.level) > int(Level.debug) {
		return
	}
	l.emit(.debug, msg, params)
}

// info logs a message at info level.
pub fn (l &Logger) info(msg string, params LogParams) {
	if int(l.level) > int(Level.info) {
		return
	}
	l.emit(.info, msg, params)
}

// warn logs a message at warn level.
pub fn (l &Logger) warn(msg string, params LogParams) {
	if int(l.level) > int(Level.warn) {
		return
	}
	l.emit(.warn, msg, params)
}

// error logs a message at error level.
pub fn (l &Logger) error(msg string, params LogParams) {
	l.emit(.error, msg, params)
}

// parse_level converts a string to a Level enum. Unknown values default to info.
pub fn parse_level(s string) Level {
	return match s {
		'debug' { .debug }
		'warn' { .warn }
		'error' { .error }
		else { .info }
	}
}

// parse_format converts a string to a Format enum. Unknown values default to human.
pub fn parse_format(s string) Format {
	return match s {
		'json' { .json }
		else { .human }
	}
}

// emit formats and outputs a log entry.
fn (l &Logger) emit(level Level, msg string, params LogParams) {
	ts := time.now().format_rfc3339()
	line := if l.format == .json {
		format_json(ts, level, l.component, msg, params)
	} else {
		format_human(ts, level, l.component, msg, params)
	}
	// Route info/debug to stdout, warn/error to stderr (Unix convention)
	if level == .warn || level == .error {
		eprintln(line)
	} else {
		println(line)
	}
}

// format_human builds a human-readable log line with ANSI colors.
fn format_human(ts string, level Level, component string, msg string, p LogParams) string {
	color, reset := level_color(level)
	mut b := strings.new_builder(128)
	b.write_string(ts)
	b.write_string(' ')
	b.write_string(color)
	b.write_string(level_str(level))
	b.write_string(reset)
	b.write_string(' [${component}] ')
	b.write_string(msg)
	if p.subdomain != '' {
		b.write_string(' subdomain=${p.subdomain}')
	}
	if p.stream_id >= 0 {
		b.write_string(' stream_id=${p.stream_id}')
	}
	if p.remote_addr != '' {
		b.write_string(' remote_addr=${p.remote_addr}')
	}
	if p.token != '' {
		b.write_string(' token=${redact_token(p.token)}')
	}
	if p.err != '' {
		b.write_string(' err=${p.err}')
	}
	if p.detail != '' {
		b.write_string(' detail=${p.detail}')
	}
	return b.str()
}

// format_json builds a single-line JSON log entry.
fn format_json(ts string, level Level, component string, msg string, p LogParams) string {
	mut b := strings.new_builder(256)
	b.write_string('{"ts":"${ts}","level":"${level_name(level)}","component":"${escape_json(component)}","msg":"${escape_json(msg)}"')
	if p.subdomain != '' {
		b.write_string(',"subdomain":"${escape_json(p.subdomain)}"')
	}
	if p.stream_id >= 0 {
		b.write_string(',"stream_id":${p.stream_id}')
	}
	if p.remote_addr != '' {
		b.write_string(',"remote_addr":"${escape_json(p.remote_addr)}"')
	}
	if p.token != '' {
		b.write_string(',"token":"${redact_token(p.token)}"')
	}
	if p.err != '' {
		b.write_string(',"err":"${escape_json(p.err)}"')
	}
	if p.detail != '' {
		b.write_string(',"detail":"${escape_json(p.detail)}"')
	}
	b.write_string('}')
	return b.str()
}

// level_str returns the padded level name for human output.
fn level_str(level Level) string {
	return match level {
		.debug { 'DEBUG' }
		.info { ' INFO' }
		.warn { ' WARN' }
		.error { 'ERROR' }
	}
}

// level_name returns the lowercase level name for JSON output.
fn level_name(level Level) string {
	return match level {
		.debug { 'debug' }
		.info { 'info' }
		.warn { 'warn' }
		.error { 'error' }
	}
}

// level_color returns ANSI color code and reset sequence for terminal output.
fn level_color(level Level) (string, string) {
	reset := '\x1b[0m'
	color := match level {
		.debug { '\x1b[36m' } // cyan
		.info { '\x1b[32m' } // green
		.warn { '\x1b[33m' } // yellow
		.error { '\x1b[31m' } // red
	}
	return color, reset
}

// redact_token returns a redacted version of a token for safe logging.
// Shows first 4 and last 4 characters: "abcd...wxyz".
// Duplicated from auth.redact_token to avoid circular imports.
fn redact_token(token string) string {
	if token.len <= 8 {
		return '****'
	}
	return '${token[..4]}...${token[token.len - 4..]}'
}

// escape_json escapes special characters in a JSON string value.
fn escape_json(s string) string {
	return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r',
		'\\r').replace('\t', '\\t')
}
