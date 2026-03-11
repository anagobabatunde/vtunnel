module slog

// --- Level ordering ---

fn test_level_ordering() {
	assert int(Level.debug) < int(Level.info), 'debug < info'
	assert int(Level.info) < int(Level.warn), 'info < warn'
	assert int(Level.warn) < int(Level.error), 'warn < error'
}

// --- parse_level ---

fn test_parse_level_valid() {
	assert parse_level('debug') == .debug
	assert parse_level('info') == .info
	assert parse_level('warn') == .warn
	assert parse_level('error') == .error
}

fn test_parse_level_unknown_defaults_to_info() {
	assert parse_level('') == .info
	assert parse_level('verbose') == .info
	assert parse_level('WARN') == .info // case-sensitive
	assert parse_level('trace') == .info
}

// --- parse_format ---

fn test_parse_format_valid() {
	assert parse_format('json') == .json
	assert parse_format('human') == .human
}

fn test_parse_format_unknown_defaults_to_human() {
	assert parse_format('') == .human
	assert parse_format('xml') == .human
	assert parse_format('JSON') == .human // case-sensitive
}

// --- redact_token ---

fn test_redact_token_normal() {
	assert redact_token('abcdefghijklmnop') == 'abcd...mnop'
}

fn test_redact_token_exactly_9_chars() {
	assert redact_token('123456789') == '1234...6789'
}

fn test_redact_token_short() {
	assert redact_token('abcd') == '****'
	assert redact_token('12345678') == '****'
}

fn test_redact_token_empty() {
	assert redact_token('') == '****'
}

fn test_redact_token_single_char() {
	assert redact_token('a') == '****'
}

// --- escape_json ---

fn test_escape_json_no_special() {
	assert escape_json('hello world') == 'hello world'
}

fn test_escape_json_quotes() {
	assert escape_json('say "hi"') == 'say \\"hi\\"'
}

fn test_escape_json_backslash() {
	assert escape_json('path\\to') == 'path\\\\to'
}

fn test_escape_json_newline() {
	assert escape_json('line1\nline2') == 'line1\\nline2'
}

fn test_escape_json_carriage_return() {
	assert escape_json('a\rb') == 'a\\rb'
}

fn test_escape_json_tab() {
	assert escape_json('a\tb') == 'a\\tb'
}

fn test_escape_json_empty() {
	assert escape_json('') == ''
}

// --- level_str ---

fn test_level_str_padding() {
	assert level_str(.debug) == 'DEBUG'
	assert level_str(.info) == ' INFO'
	assert level_str(.warn) == ' WARN'
	assert level_str(.error) == 'ERROR'
}

// --- level_name ---

fn test_level_name_lowercase() {
	assert level_name(.debug) == 'debug'
	assert level_name(.info) == 'info'
	assert level_name(.warn) == 'warn'
	assert level_name(.error) == 'error'
}

// --- level_color ---

fn test_level_color_returns_ansi_codes() {
	color, reset := level_color(.info)
	assert color.len > 0, 'color should not be empty'
	assert reset == '\x1b[0m', 'reset should be ANSI reset'
}

fn test_level_color_different_per_level() {
	dc, _ := level_color(.debug)
	ic, _ := level_color(.info)
	wc, _ := level_color(.warn)
	ec, _ := level_color(.error)
	// All colors should be different
	assert dc != ic
	assert ic != wc
	assert wc != ec
}

// --- format_human ---

fn test_format_human_basic() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'server', 'started', LogParams{})
	assert line.contains('INFO'), 'should contain level'
	assert line.contains('[server]'), 'should contain component'
	assert line.contains('started'), 'should contain message'
	assert line.contains('2026-01-01T00:00:00Z'), 'should contain timestamp'
}

fn test_format_human_with_subdomain() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'control', 'tunnel registered',
		LogParams{
		subdomain: 'myapp'
	})
	assert line.contains('subdomain=myapp')
}

fn test_format_human_with_stream_id() {
	line := format_human('2026-01-01T00:00:00Z', .warn, 'stream', 'buffer full', LogParams{
		stream_id: 42
	})
	assert line.contains('stream_id=42')
}

fn test_format_human_stream_id_unset() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'test', 'msg', LogParams{})
	assert !line.contains('stream_id'), 'unset stream_id should be omitted'
}

fn test_format_human_with_token_redacted() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'control', 'authenticated', LogParams{
		token: 'abcdefghijklmnop'
	})
	assert line.contains('token=abcd...mnop'), 'token should be redacted'
	assert !line.contains('abcdefghijklmnop'), 'full token should not appear'
}

fn test_format_human_with_err() {
	line := format_human('2026-01-01T00:00:00Z', .error, 'acme', 'renewal failed', LogParams{
		err: 'connection timeout'
	})
	assert line.contains('err=connection timeout')
}

fn test_format_human_with_detail() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'server', 'TLS enabled', LogParams{
		detail: '/path/to/cert.pem'
	})
	assert line.contains('detail=/path/to/cert.pem')
}

fn test_format_human_with_remote_addr() {
	line := format_human('2026-01-01T00:00:00Z', .info, 'control', 'connected', LogParams{
		remote_addr: '192.168.1.1:54321'
	})
	assert line.contains('remote_addr=192.168.1.1:54321')
}

fn test_format_human_all_fields() {
	line := format_human('2026-01-01T00:00:00Z', .debug, 'control', 'processing', LogParams{
		subdomain:   'app'
		stream_id:   7
		remote_addr: '10.0.0.1:1234'
		token:       'abcdefghijklmnop'
		err:         'timeout'
		detail:      'extra info'
	})
	assert line.contains('subdomain=app')
	assert line.contains('stream_id=7')
	assert line.contains('remote_addr=10.0.0.1:1234')
	assert line.contains('token=abcd...mnop')
	assert line.contains('err=timeout')
	assert line.contains('detail=extra info')
}

// --- format_json ---

fn test_format_json_basic() {
	line := format_json('2026-01-01T00:00:00Z', .info, 'server', 'started', LogParams{})
	assert line.starts_with('{'), 'should start with {'
	assert line.ends_with('}'), 'should end with }'
	assert line.contains('"level":"info"')
	assert line.contains('"component":"server"')
	assert line.contains('"msg":"started"')
	assert line.contains('"ts":"2026-01-01T00:00:00Z"')
}

fn test_format_json_with_subdomain() {
	line := format_json('2026-01-01T00:00:00Z', .info, 'control', 'registered', LogParams{
		subdomain: 'myapp'
	})
	assert line.contains('"subdomain":"myapp"')
}

fn test_format_json_with_stream_id() {
	line := format_json('2026-01-01T00:00:00Z', .warn, 'stream', 'full', LogParams{
		stream_id: 42
	})
	assert line.contains('"stream_id":42')
}

fn test_format_json_omits_unset_fields() {
	line := format_json('2026-01-01T00:00:00Z', .info, 'test', 'msg', LogParams{})
	assert !line.contains('subdomain')
	assert !line.contains('stream_id')
	assert !line.contains('remote_addr')
	assert !line.contains('token')
	assert !line.contains('err')
	assert !line.contains('detail')
}

fn test_format_json_token_redacted() {
	line := format_json('2026-01-01T00:00:00Z', .info, 'control', 'auth', LogParams{
		token: 'abcdefghijklmnop'
	})
	assert line.contains('abcd...mnop'), 'token should be redacted in JSON'
	assert !line.contains('abcdefghijklmnop'), 'full token should not appear'
}

fn test_format_json_escapes_quotes_in_msg() {
	line := format_json('2026-01-01T00:00:00Z', .error, 'test', 'bad "input"', LogParams{})
	assert line.contains('\\"input\\"'), 'quotes in msg should be escaped'
}

fn test_format_json_escapes_quotes_in_err() {
	line := format_json('2026-01-01T00:00:00Z', .error, 'test', 'failed', LogParams{
		err: 'got "null"'
	})
	assert line.contains('\\"null\\"'), 'quotes in err should be escaped'
}

// --- new / with_component ---

fn test_new_creates_logger() {
	l := new('server', .info, .human)
	assert l.component == 'server'
	assert l.level == .info
	assert l.format == .human
}

fn test_new_debug_level() {
	l := new('test', .debug, .json)
	assert l.level == .debug
	assert l.format == .json
}

fn test_with_component_creates_child() {
	parent := new('server', .warn, .json)
	child := parent.with_component('control')
	assert child.component == 'control'
	assert child.level == .warn, 'child inherits parent level'
	assert child.format == .json, 'child inherits parent format'
}

fn test_with_component_does_not_modify_parent() {
	parent := new('server', .info, .human)
	_ := parent.with_component('control')
	assert parent.component == 'server', 'parent should be unchanged'
}

// --- level filtering (no crash tests) ---

fn test_logger_warn_level_filters_debug_and_info() {
	l := new('test', .warn, .human)
	// These should be silently filtered (no crash, no output)
	l.debug('should not appear')
	l.info('should not appear')
	// These should work without crashing
	l.warn('warning message')
	l.error('error message')
}

fn test_logger_error_level_filters_all_below() {
	l := new('test', .error, .human)
	l.debug('filtered')
	l.info('filtered')
	l.warn('filtered')
	l.error('only this should appear')
}

fn test_logger_debug_level_allows_all() {
	l := new('test', .debug, .human)
	l.debug('visible')
	l.info('visible')
	l.warn('visible')
	l.error('visible')
}
