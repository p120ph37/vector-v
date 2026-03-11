module vrl

import time

// Parser turns a token stream into an AST.
pub struct Parser {
	tokens []Token
mut:
	pos int
}

pub fn new_parser(tokens []Token) Parser {
	return Parser{
		tokens: tokens
	}
}

// parse parses the full program as a sequence of expressions.
// Returns the last expression's value (VRL program returns last expression).
pub fn (mut p Parser) parse() !Expr {
	mut exprs := []Expr{}
	for p.current().kind != .eof {
		p.skip_newlines()
		if p.current().kind == .eof {
			break
		}
		expr := p.parse_expr()!
		exprs << expr
		p.skip_newlines()
	}
	if exprs.len == 0 {
		return Expr(LiteralExpr{value: VrlValue(VrlNull{})})
	}
	if exprs.len == 1 {
		return exprs[0]
	}
	return Expr(BlockExpr{exprs: exprs})
}

fn (mut p Parser) parse_expr() !Expr {
	return p.parse_assignment()
}

fn (mut p Parser) parse_assignment() !Expr {
	left := p.parse_coalesce()!

	if p.current().kind == .assign {
		p.advance()
		p.skip_newlines()
		right := p.parse_assignment()!
		return Expr(AssignExpr{
			target: [left]
			value: [right]
		})
	}

	if p.current().kind == .pipe_assign {
		p.advance()
		right := p.parse_assignment()!
		return Expr(MergeAssignExpr{
			target: [left]
			value: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_coalesce() !Expr {
	mut left := p.parse_or()!

	for p.current().kind == .question2 {
		p.advance()
		p.skip_newlines()
		right := p.parse_or()!
		left = Expr(CoalesceExpr{
			expr: [left]
			default_: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_or() !Expr {
	mut left := p.parse_and()!

	for p.current().kind == .or || p.current().kind == .pipe {
		if p.current().kind == .pipe {
			// Single | is object merge
			p.advance()
			p.skip_newlines()
			right := p.parse_and()!
			left = Expr(BinaryExpr{
				op: '|'
				left: [left]
				right: [right]
			})
		} else {
			p.advance()
			p.skip_newlines()
			right := p.parse_and()!
			left = Expr(BinaryExpr{
				op: '||'
				left: [left]
				right: [right]
			})
		}
	}

	return left
}

fn (mut p Parser) parse_and() !Expr {
	mut left := p.parse_equality()!

	for p.current().kind == .and {
		p.advance()
		p.skip_newlines()
		right := p.parse_equality()!
		left = Expr(BinaryExpr{
			op: '&&'
			left: [left]
			right: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_equality() !Expr {
	mut left := p.parse_comparison()!

	for p.current().kind in [.eq, .neq] {
		op := p.current().lit
		p.advance()
		p.skip_newlines()
		right := p.parse_comparison()!
		left = Expr(BinaryExpr{
			op: op
			left: [left]
			right: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_comparison() !Expr {
	mut left := p.parse_addition()!

	for p.current().kind in [.lt, .gt, .le, .ge] {
		op := p.current().lit
		p.advance()
		p.skip_newlines()
		right := p.parse_addition()!
		left = Expr(BinaryExpr{
			op: op
			left: [left]
			right: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_addition() !Expr {
	mut left := p.parse_multiplication()!

	for p.current().kind in [.plus, .minus] {
		op := p.current().lit
		p.advance()
		p.skip_newlines()
		right := p.parse_multiplication()!
		left = Expr(BinaryExpr{
			op: op
			left: [left]
			right: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_multiplication() !Expr {
	mut left := p.parse_unary()!

	for p.current().kind in [.star, .slash, .percent] {
		op := p.current().lit
		p.advance()
		p.skip_newlines()
		right := p.parse_unary()!
		left = Expr(BinaryExpr{
			op: op
			left: [left]
			right: [right]
		})
	}

	return left
}

fn (mut p Parser) parse_unary() !Expr {
	if p.current().kind == .not {
		p.advance()
		expr := p.parse_unary()!
		return Expr(NotExpr{expr: [expr]})
	}
	if p.current().kind == .minus {
		p.advance()
		expr := p.parse_postfix()!
		return Expr(UnaryExpr{op: '-', expr: [expr]})
	}
	return p.parse_postfix()
}

fn (mut p Parser) parse_postfix() !Expr {
	mut expr := p.parse_primary()!

	for {
		// Handle postfix indexing: expr[index]
		if p.current().kind == .lbracket {
			p.advance()
			index := p.parse_expr()!
			if p.current().kind == .rbracket {
				p.advance()
			}
			expr = Expr(IndexExpr{
				expr: [expr]
				index: [index]
			})
			continue
		}
		// Handle postfix property access: expr.ident
		if p.current().kind == .dot_ident {
			path := p.current().lit // e.g. ".foo" or ".foo.bar"
			p.advance()
			// Extract the property name(s) from the dot_ident
			clean := if path.starts_with('.') { path[1..] } else { path }
			parts := clean.split('.')
			for part in parts {
				expr = Expr(IndexExpr{
					expr: [expr]
					index: [Expr(LiteralExpr{value: VrlValue(part)})]
				})
			}
			continue
		}
		if p.current().kind == .dot && p.pos + 1 < p.tokens.len
			&& p.tokens[p.pos + 1].kind == .ident {
			p.advance() // skip .
			prop := p.current().lit
			p.advance()
			expr = Expr(IndexExpr{
				expr: [expr]
				index: [Expr(LiteralExpr{value: VrlValue(prop)})]
			})
			continue
		}
		break
	}

	return expr
}

fn (mut p Parser) parse_primary() !Expr {
	tok := p.current()

	match tok.kind {
		.integer {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(tok.lit.int())})
		}
		.float {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(tok.lit.f64())})
		}
		.string_lit, .raw_string {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(tok.lit)})
		}
		.template_lit {
			p.advance()
			return p.parse_template(tok.lit)
		}
		.regex_lit {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(VrlRegex{pattern: tok.lit})})
		}
		.timestamp_lit {
			p.advance()
			ts := parse_timestamp_lit(tok.lit)
			return Expr(LiteralExpr{value: VrlValue(ts)})
		}
		.true_lit {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(true)})
		}
		.false_lit {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(false)})
		}
		.null_lit {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(VrlNull{})})
		}
		.dot_ident {
			p.advance()
			if tok.lit == '.' {
				return Expr(PathExpr{path: '.'})
			}
			return Expr(PathExpr{path: tok.lit})
		}
		.dot {
			p.advance()
			return Expr(PathExpr{path: '.'})
		}
		.meta_ident {
			p.advance()
			return Expr(MetaPathExpr{path: tok.lit})
		}
		.ident {
			return p.parse_ident_or_call()
		}
		.lparen {
			p.advance()
			p.skip_newlines()
			mut exprs := []Expr{}
			for p.current().kind != .rparen && p.current().kind != .eof {
				expr := p.parse_expr()!
				exprs << expr
				p.skip_newlines()
				if p.current().kind == .semicolon {
					p.advance()
					p.skip_newlines()
				}
			}
			if p.current().kind == .rparen {
				p.advance()
			}
			if exprs.len == 0 {
				return Expr(LiteralExpr{value: VrlValue(VrlNull{})})
			}
			if exprs.len == 1 {
				return exprs[0]
			}
			return Expr(BlockExpr{exprs: exprs})
		}
		.lbracket {
			return p.parse_array()
		}
		.lbrace {
			// Distinguish between object literal and block expression.
			// Object: { } or { string/ident : ... }
			// Block: anything else (e.g. { 5 }, { foo = 1; ... })
			// Skip newlines when peeking ahead
			mut peek := p.pos + 1
			for peek < p.tokens.len && (p.tokens[peek].kind == .newline || p.tokens[peek].kind == .semicolon) {
				peek++
			}
			next := if peek < p.tokens.len { p.tokens[peek] } else { Token{kind: .eof} }
			if next.kind == .rbrace {
				// Empty object {}
				return p.parse_object()
			}
			if next.kind == .string_lit || next.kind == .raw_string {
				peek2 := peek + 1
				after := if peek2 < p.tokens.len { p.tokens[peek2] } else { Token{kind: .eof} }
				if after.kind == .colon {
					return p.parse_object()
				}
				return p.parse_block()
			}
			if next.kind == .ident {
				peek2 := peek + 1
				after := if peek2 < p.tokens.len { p.tokens[peek2] } else { Token{kind: .eof} }
				if after.kind == .colon {
					return p.parse_object()
				}
				return p.parse_block()
			}
			// Default to block for everything else
			return p.parse_block()
		}
		.minus {
			p.advance()
			expr := p.parse_primary()!
			return Expr(UnaryExpr{op: '-', expr: [expr]})
		}
		else {
			p.advance()
			return Expr(LiteralExpr{value: VrlValue(VrlNull{})})
		}
	}
}

fn (mut p Parser) parse_ident_or_call() !Expr {
	name := p.current().lit
	p.advance()

	if name == 'if' {
		return p.parse_if()
	}

	if name == 'abort' {
		if p.current().kind != .eof && p.current().kind != .newline
			&& p.current().kind != .rbrace {
			msg := p.parse_expr()!
			return Expr(AbortExpr{message: [msg]})
		}
		return Expr(AbortExpr{})
	}

	if name == 'return' {
		if p.current().kind != .eof && p.current().kind != .newline
			&& p.current().kind != .rbrace {
			val := p.parse_expr()!
			return Expr(ReturnExpr{value: [val]})
		}
		return Expr(ReturnExpr{})
	}

	if p.current().kind == .lparen {
		return p.parse_fn_call(name)
	}

	if p.current().kind == .assign {
		p.advance()
		p.skip_newlines()
		val := p.parse_expr()!
		return Expr(AssignExpr{
			target: [Expr(IdentExpr{name: name})]
			value: [val]
		})
	}

	return Expr(IdentExpr{name: name})
}

fn (mut p Parser) parse_fn_call(name string) !Expr {
	p.advance() // skip (
	mut args := []Expr{}
	for p.current().kind != .rparen && p.current().kind != .eof {
		p.skip_newlines()
		if p.current().kind == .rparen {
			break
		}
		// Handle named arguments: name: expr
		if p.current().kind == .ident && p.pos + 1 < p.tokens.len
			&& p.tokens[p.pos + 1].kind == .colon {
			p.advance() // skip name
			p.advance() // skip :
		}
		arg := p.parse_expr()!
		args << arg
		p.skip_newlines()
		if p.current().kind == .comma {
			p.advance()
		}
	}
	if p.current().kind == .rparen {
		p.advance()
	}

	// Check for closure: -> |params| { body }
	mut closure := []Expr{}
	if p.current().kind == .arrow {
		p.advance()
		cl := p.parse_closure()!
		closure = [cl]
	}

	return Expr(FnCallExpr{
		name: name
		args: args
		closure: closure
	})
}

fn (mut p Parser) parse_closure() !Expr {
	// Parse |param1, param2| { body }
	mut params := []string{}
	if p.current().kind == .or {
		// || means empty params
		p.advance()
	} else {
		if p.current().lit == '|' || p.current().kind == .or {
			p.advance()
		}
		for p.current().kind != .eof {
			if p.current().lit == '|' {
				p.advance()
				break
			}
			if p.current().kind == .ident || p.current().kind == .dot_ident {
				params << p.current().lit
				p.advance()
			}
			if p.current().kind == .comma {
				p.advance()
			}
		}
	}
	p.skip_newlines()
	body := p.parse_block_or_expr()!
	return Expr(ClosureExpr{
		params: params
		body: [body]
	})
}

fn (mut p Parser) parse_block_or_expr() !Expr {
	if p.current().kind == .lbrace {
		return p.parse_block()
	}
	return p.parse_expr()
}

fn (mut p Parser) parse_block() !Expr {
	p.advance() // skip {
	mut exprs := []Expr{}
	for p.current().kind != .rbrace && p.current().kind != .eof {
		p.skip_newlines()
		if p.current().kind == .rbrace {
			break
		}
		expr := p.parse_expr()!
		exprs << expr
		p.skip_newlines()
	}
	if p.current().kind == .rbrace {
		p.advance()
	}
	if exprs.len == 0 {
		return Expr(LiteralExpr{value: VrlValue(VrlNull{})})
	}
	if exprs.len == 1 {
		return exprs[0]
	}
	return Expr(BlockExpr{exprs: exprs})
}

fn (mut p Parser) parse_if() !Expr {
	condition := p.parse_expr()!
	p.skip_newlines()
	then_block := p.parse_block()!

	// Peek ahead past newlines/semicolons to check for 'else', but only
	// consume them if 'else' actually follows. This prevents eating
	// statement separators that belong to the enclosing scope.
	saved_pos := p.pos
	p.skip_newlines()

	if p.current().kind == .ident && p.current().lit == 'else' {
		p.advance()
		p.skip_newlines()
		if p.current().kind == .ident && p.current().lit == 'if' {
			p.advance()
			else_block := p.parse_if()!
			return Expr(IfExpr{
				condition: [condition]
				then_block: [then_block]
				else_block: [else_block]
			})
		}
		else_block := p.parse_block()!
		return Expr(IfExpr{
			condition: [condition]
			then_block: [then_block]
			else_block: [else_block]
		})
	}

	// No 'else' found — restore position so the separator is not consumed
	p.pos = saved_pos
	return Expr(IfExpr{
		condition: [condition]
		then_block: [then_block]
	})
}

fn (mut p Parser) parse_array() !Expr {
	p.advance() // skip [
	mut items := []Expr{}
	for p.current().kind != .rbracket && p.current().kind != .eof {
		p.skip_newlines()
		if p.current().kind == .rbracket {
			break
		}
		item := p.parse_expr()!
		items << item
		p.skip_newlines()
		if p.current().kind == .comma {
			p.advance()
		}
	}
	if p.current().kind == .rbracket {
		p.advance()
	}
	return Expr(ArrayExpr{items: items})
}

fn (mut p Parser) parse_object() !Expr {
	p.advance() // skip {
	mut pairs := []KeyValue{}
	for p.current().kind != .rbrace && p.current().kind != .eof {
		p.skip_newlines()
		if p.current().kind == .rbrace {
			break
		}
		key := if p.current().kind == .string_lit {
			k := p.current().lit
			p.advance()
			k
		} else if p.current().kind == .ident {
			k := p.current().lit
			p.advance()
			k
		} else {
			p.advance()
			''
		}
		if p.current().kind == .colon {
			p.advance()
		}
		p.skip_newlines()
		val := p.parse_expr()!
		pairs << KeyValue{key: key, value: val}
		p.skip_newlines()
		if p.current().kind == .comma {
			p.advance()
		}
	}
	if p.current().kind == .rbrace {
		p.advance()
	}
	return Expr(ObjectExpr{pairs: pairs})
}

fn (p &Parser) current() Token {
	if p.pos >= p.tokens.len {
		return Token{kind: .eof}
	}
	return p.tokens[p.pos]
}

fn (mut p Parser) advance() {
	p.pos++
}

fn (mut p Parser) skip_newlines() {
	for p.current().kind == .newline || p.current().kind == .semicolon {
		p.advance()
	}
}

// parse_template parses a template string like "hello {{ expr }} world"
// into a chain of string concatenations.
fn (mut p Parser) parse_template(s string) !Expr {
	mut parts := []Expr{}
	mut remaining := s
	for remaining.len > 0 {
		idx := remaining.index('{{') or {
			// No more templates, rest is literal string
			parts << Expr(LiteralExpr{value: VrlValue(remaining)})
			break
		}
		// Add the literal part before {{
		if idx > 0 {
			parts << Expr(LiteralExpr{value: VrlValue(remaining[..idx])})
		}
		// Find the closing }}
		after := remaining[idx + 2..]
		end_idx := after.index('}}') or {
			// No closing }}, treat rest as literal
			parts << Expr(LiteralExpr{value: VrlValue(remaining[idx..])})
			break
		}
		// Parse the expression between {{ and }}
		expr_str := after[..end_idx].trim_space()
		mut sub_lex := new_lexer(expr_str)
		sub_tokens := sub_lex.tokenize()
		mut sub_parser := new_parser(sub_tokens)
		expr := sub_parser.parse()!
		// Wrap in to_string call so the expression result is coerced to string
		parts << Expr(FnCallExpr{
			name: 'to_string'
			args: [expr]
		})
		remaining = after[end_idx + 2..]
	}
	if parts.len == 0 {
		return Expr(LiteralExpr{value: VrlValue('')})
	}
	if parts.len == 1 {
		return parts[0]
	}
	// Chain all parts with + (string concatenation)
	mut result := parts[0]
	for i in 1 .. parts.len {
		result = Expr(BinaryExpr{
			op: '+'
			left: [result]
			right: [parts[i]]
		})
	}
	return result
}

// parse_timestamp_lit parses an RFC3339 timestamp string like "2021-02-02T19:41:00Z"
fn parse_timestamp_lit(s string) Timestamp {
	// Try RFC3339 format: 2021-02-02T19:41:00Z or with offset
	t := time.parse_rfc3339(s) or {
		// Try other common formats
		time.parse(s) or {
			return Timestamp{}
		}
	}
	return Timestamp{t: t}
}
