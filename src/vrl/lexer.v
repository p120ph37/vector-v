module vrl

// Token types for VRL lexing.
pub enum TokenKind {
	// Literals
	integer       // 42
	float         // 3.14
	string_lit    // "hello"
	raw_string    // s'hello'
	regex_lit     // r'pattern'
	timestamp_lit // t'2024-01-01T00:00:00Z'
	true_lit      // true
	false_lit     // false
	null_lit      // null
	// Identifiers and paths
	ident      // foo
	dot_ident  // .foo or .foo.bar
	meta_ident // %foo
	// Operators
	plus     // +
	minus    // -
	star     // *
	slash    // /
	percent  // %
	eq       // ==
	neq      // !=
	lt       // <
	gt       // >
	le       // <=
	ge       // >=
	and      // &&
	or       // ||
	not      // !
	assign   // =
	pipe_assign // |=
	question2 // ?? (error coalescing)
	// Delimiters
	lparen    // (
	rparen    // )
	lbracket  // [
	rbracket  // ]
	lbrace    // {
	rbrace    // }
	comma     // ,
	colon     // :
	semicolon // ;
	dot       // .
	arrow     // ->
	// Special
	newline // \n
	eof
}

pub struct Token {
pub:
	kind    TokenKind
	lit     string
	line    int
	col     int
}

pub fn (t Token) str() string {
	return '${t.kind}(${t.lit})'
}

// Lexer tokenizes VRL source code.
pub struct Lexer {
	src string
mut:
	pos       int
	line      int = 1
	col       int = 1
	last_kind TokenKind = .eof
}

pub fn new_lexer(src string) Lexer {
	return Lexer{
		src: src
	}
}

pub fn (mut l Lexer) tokenize() []Token {
	mut tokens := []Token{}
	for {
		tok := l.next_token()
		if tok.kind != .newline {
			l.last_kind = tok.kind
		}
		tokens << tok
		if tok.kind == .eof {
			break
		}
	}
	return tokens
}

fn (mut l Lexer) next_token() Token {
	l.skip_whitespace_and_comments()
	if l.pos >= l.src.len {
		return Token{kind: .eof, line: l.line, col: l.col}
	}

	start_line := l.line
	start_col := l.col
	ch := l.src[l.pos]

	// Newlines
	if ch == `\n` {
		l.advance()
		return Token{kind: .newline, lit: '\\n', line: start_line, col: start_col}
	}

	// Numbers
	if ch.is_digit() || (ch == `-` && l.pos + 1 < l.src.len && l.src[l.pos + 1].is_digit()) {
		return l.read_number(start_line, start_col)
	}

	// String literals
	if ch == `"` {
		return l.read_string(start_line, start_col)
	}

	// Prefixed strings: s'...', r'...', t'...'
	if (ch == `s` || ch == `r` || ch == `t`) && l.pos + 1 < l.src.len
		&& l.src[l.pos + 1] == `'` {
		return l.read_prefixed_string(ch, start_line, start_col)
	}

	// Single-quoted strings (regular)
	if ch == `'` {
		return l.read_single_string(start_line, start_col)
	}

	// Dot paths: .foo.bar
	if ch == `.` && l.pos + 1 < l.src.len && (l.src[l.pos + 1].is_letter()
		|| l.src[l.pos + 1] == `_`) {
		return l.read_dot_path(start_line, start_col)
	}

	// % can be modulo operator (after value) or metadata path/root
	if ch == `%` {
		// After a value-producing token, % is the modulo operator
		if l.last_kind in [.integer, .float, .string_lit, .true_lit, .false_lit,
			.null_lit, .ident, .rparen, .rbracket, .dot_ident] {
			l.advance()
			return Token{kind: .percent, lit: '%', line: start_line, col: start_col}
		}
		// Otherwise it's a metadata path
		if l.pos + 1 < l.src.len && (l.src[l.pos + 1].is_letter()
			|| l.src[l.pos + 1] == `_`) {
			return l.read_meta_path(start_line, start_col)
		}
		// Bare % (metadata root)
		l.advance()
		return Token{kind: .meta_ident, lit: '%', line: start_line, col: start_col}
	}

	// Identifiers and keywords
	if ch.is_letter() || ch == `_` {
		return l.read_ident(start_line, start_col)
	}

	// Two-character operators
	if l.pos + 1 < l.src.len {
		two := l.src[l.pos..l.pos + 2]
		kind := match two {
			'==' { TokenKind.eq }
			'!=' { TokenKind.neq }
			'<=' { TokenKind.le }
			'>=' { TokenKind.ge }
			'&&' { TokenKind.and }
			'||' { TokenKind.or }
			'??' { TokenKind.question2 }
			'|=' { TokenKind.pipe_assign }
			'->' { TokenKind.arrow }
			else { TokenKind.eof }
		}
		if kind != .eof {
			l.advance()
			l.advance()
			return Token{kind: kind, lit: two, line: start_line, col: start_col}
		}
	}

	// Single-character operators
	kind := match ch {
		`+` { TokenKind.plus }
		`-` { TokenKind.minus }
		`*` { TokenKind.star }
		`/` { TokenKind.slash }
		`=` { TokenKind.assign }
		`<` { TokenKind.lt }
		`>` { TokenKind.gt }
		`!` { TokenKind.not }
		`(` { TokenKind.lparen }
		`)` { TokenKind.rparen }
		`[` { TokenKind.lbracket }
		`]` { TokenKind.rbracket }
		`{` { TokenKind.lbrace }
		`}` { TokenKind.rbrace }
		`,` { TokenKind.comma }
		`:` { TokenKind.colon }
		`;` { TokenKind.semicolon }
		`.` { TokenKind.dot }
		else { TokenKind.eof }
	}
	if kind != .eof || ch == `.` {
		l.advance()
		actual_kind := if ch == `.` { TokenKind.dot } else { kind }
		return Token{kind: actual_kind, lit: ch.ascii_str(), line: start_line, col: start_col}
	}

	// Unknown character - skip
	l.advance()
	return l.next_token()
}

fn (mut l Lexer) advance() {
	if l.pos < l.src.len {
		if l.src[l.pos] == `\n` {
			l.line++
			l.col = 1
		} else {
			l.col++
		}
		l.pos++
	}
}

fn (mut l Lexer) skip_whitespace_and_comments() {
	for l.pos < l.src.len {
		ch := l.src[l.pos]
		if ch == ` ` || ch == `\t` || ch == `\r` {
			l.advance()
			continue
		}
		// Line comments
		if ch == `#` {
			for l.pos < l.src.len && l.src[l.pos] != `\n` {
				l.advance()
			}
			continue
		}
		// Block comments //
		if ch == `/` && l.pos + 1 < l.src.len && l.src[l.pos + 1] == `/` {
			for l.pos < l.src.len && l.src[l.pos] != `\n` {
				l.advance()
			}
			continue
		}
		break
	}
}

fn (mut l Lexer) read_number(line int, col int) Token {
	start := l.pos
	if l.src[l.pos] == `-` {
		l.advance()
	}
	for l.pos < l.src.len && (l.src[l.pos].is_digit() || l.src[l.pos] == `_`) {
		l.advance()
	}
	// Check for float
	if l.pos < l.src.len && l.src[l.pos] == `.` && l.pos + 1 < l.src.len
		&& l.src[l.pos + 1].is_digit() {
		l.advance() // skip .
		for l.pos < l.src.len && (l.src[l.pos].is_digit() || l.src[l.pos] == `_`) {
			l.advance()
		}
		lit := l.src[start..l.pos].replace('_', '')
		return Token{kind: .float, lit: lit, line: line, col: col}
	}
	lit := l.src[start..l.pos].replace('_', '')
	return Token{kind: .integer, lit: lit, line: line, col: col}
}

fn (mut l Lexer) read_string(line int, col int) Token {
	l.advance() // skip opening "
	mut result := []u8{}
	for l.pos < l.src.len && l.src[l.pos] != `"` {
		if l.src[l.pos] == `\\` && l.pos + 1 < l.src.len {
			l.advance()
			match l.src[l.pos] {
				`n` { result << `\n` }
				`t` { result << `\t` }
				`r` { result << `\r` }
				`\\` { result << `\\` }
				`"` { result << `"` }
				`'` { result << `'` }
				`{` { result << `{` }
				`}` { result << `}` }
				else { result << l.src[l.pos] }
			}
		} else {
			result << l.src[l.pos]
		}
		l.advance()
	}
	if l.pos < l.src.len {
		l.advance() // skip closing "
	}
	return Token{kind: .string_lit, lit: result.bytestr(), line: line, col: col}
}

fn (mut l Lexer) read_single_string(line int, col int) Token {
	l.advance() // skip opening '
	mut result := []u8{}
	for l.pos < l.src.len && l.src[l.pos] != `'` {
		if l.src[l.pos] == `\\` && l.pos + 1 < l.src.len {
			l.advance()
			match l.src[l.pos] {
				`n` { result << `\n` }
				`t` { result << `\t` }
				`\\` { result << `\\` }
				`'` { result << `'` }
				else { result << l.src[l.pos] }
			}
		} else {
			result << l.src[l.pos]
		}
		l.advance()
	}
	if l.pos < l.src.len {
		l.advance() // skip closing '
	}
	return Token{kind: .string_lit, lit: result.bytestr(), line: line, col: col}
}

fn (mut l Lexer) read_prefixed_string(prefix u8, line int, col int) Token {
	l.advance() // skip prefix
	l.advance() // skip opening '
	mut result := []u8{}
	for l.pos < l.src.len && l.src[l.pos] != `'` {
		if l.src[l.pos] == `\\` && l.pos + 1 < l.src.len {
			l.advance()
			match l.src[l.pos] {
				`'` { result << `'` }
				`\\` { result << `\\` }
				else {
					result << `\\`
					result << l.src[l.pos]
				}
			}
		} else {
			result << l.src[l.pos]
		}
		l.advance()
	}
	if l.pos < l.src.len {
		l.advance() // skip closing '
	}
	kind := match prefix {
		`r` { TokenKind.regex_lit }
		`t` { TokenKind.timestamp_lit }
		else { TokenKind.raw_string }
	}
	return Token{kind: kind, lit: result.bytestr(), line: line, col: col}
}

fn (mut l Lexer) read_dot_path(line int, col int) Token {
	start := l.pos
	l.advance() // skip initial .
	for l.pos < l.src.len
		&& (l.src[l.pos].is_letter() || l.src[l.pos].is_digit() || l.src[l.pos] == `_`
		|| l.src[l.pos] == `.`) {
		l.advance()
	}
	// Check for array index like .foo[0]
	if l.pos < l.src.len && l.src[l.pos] == `[` {
		for l.pos < l.src.len && l.src[l.pos] != `]` {
			l.advance()
		}
		if l.pos < l.src.len {
			l.advance() // skip ]
		}
	}
	return Token{kind: .dot_ident, lit: l.src[start..l.pos], line: line, col: col}
}

fn (mut l Lexer) read_meta_path(line int, col int) Token {
	start := l.pos
	l.advance() // skip %
	for l.pos < l.src.len
		&& (l.src[l.pos].is_letter() || l.src[l.pos].is_digit() || l.src[l.pos] == `_`
		|| l.src[l.pos] == `.`) {
		l.advance()
	}
	return Token{kind: .meta_ident, lit: l.src[start..l.pos], line: line, col: col}
}

fn (mut l Lexer) read_ident(line int, col int) Token {
	start := l.pos
	for l.pos < l.src.len
		&& (l.src[l.pos].is_letter() || l.src[l.pos].is_digit() || l.src[l.pos] == `_`) {
		l.advance()
	}
	lit := l.src[start..l.pos]
	// Check for function call with ! (e.g., assert!, to_string!)
	if l.pos < l.src.len && l.src[l.pos] == `!` {
		l.advance()
		return Token{kind: .ident, lit: '${lit}!', line: line, col: col}
	}
	// Keywords
	kind := match lit {
		'true' { TokenKind.true_lit }
		'false' { TokenKind.false_lit }
		'null' { TokenKind.null_lit }
		else { TokenKind.ident }
	}
	return Token{kind: kind, lit: lit, line: line, col: col}
}
