module vrl

import regex.pcre

// fn_redact implements the VRL redact() function.
// redact(value, filters) - redacts sensitive data from strings.
// Filters is an array of filter objects like [{"type": "credit_card"}].
// Supported filter types: credit_card, us_social_security_number, pattern.
fn fn_redact(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('redact requires 2 arguments')
	}
	a := args[0]
	// If value is an object, redact all string fields recursively
	match a {
		ObjectMap {
			return redact_object(a, args)
		}
		else {}
	}
	s := match a {
		string { a }
		else { return error('redact requires a string or object as first argument') }
	}
	filters := args[1]
	filter_items := match filters {
		[]VrlValue { filters }
		else { return error('redact requires an array of filters as second argument') }
	}
	mut result := s
	for item in filter_items {
		match item {
			string {
				// String shorthand: "us_social_security_number", "credit_card"
				result = redact_apply_filter_type(result, item) or { return err }
			}
			VrlRegex {
				// Regex filter
				result = redact_replace(result, item.pattern)
			}
			ObjectMap {
				ft := item.get('type') or { continue }
				filter_type := match ft {
					string { ft }
					else { return error('unknown filter name') }
				}
				match filter_type {
					'pattern' {
						if pat := item.get('patterns') {
							match pat {
								[]VrlValue {
									for p in pat {
										if p is string {
											result = redact_replace(result, p)
										} else if p is VrlRegex {
											result = redact_replace(result, p.pattern)
										}
									}
								}
								else {}
							}
						}
					}
					else {
						result = redact_apply_filter_type(result, filter_type) or { return err }
					}
				}
			}
			else {
				return error('redact filter must be an object or string')
			}
		}
	}
	return VrlValue(result)
}

fn redact_apply_filter_type(s string, filter_type string) !string {
	match filter_type {
		'credit_card' {
			return redact_replace(s, r'\b\d{13,19}\b')
		}
		'us_social_security_number' {
			return redact_replace(s, r'\b\d{3}-\d{2}-\d{4}\b')
		}
		else {
			return error('unknown filter name "${filter_type}"')
		}
	}
}

// redact_replace replaces all regex matches in s with "[REDACTED]".
fn redact_replace(s string, pattern string) string {
	re := pcre.compile(pattern) or { return s }
	return pcre_replace_all(re, s, '[REDACTED]')
}

// redact_object applies redact to all string values in an object
fn redact_object(obj ObjectMap, args []VrlValue) !VrlValue {
	mut result := new_object_map()
	keys := obj.keys()
	for key in keys {
		v := obj.get(key) or { continue }
		match v {
			string {
				mut new_args := args.clone()
				new_args[0] = VrlValue(v)
				rv := fn_redact(new_args)!
				result.set(key, rv)
			}
			else {
				result.set(key, v)
			}
		}
	}
	return VrlValue(result)
}

// match_datadog_query(value, query) - matches an object against a Datadog Search Syntax query.
// Supports: field:value, @attr:value, wildcards (*/?), prefix matching (val*),
// quoted phrases ("foo bar"), ranges ([a TO b]), comparisons (>/</>=/<=),
// boolean operators (AND/OR/NOT/-), _exists_/_missing_, and *:* (match all).
fn fn_match_datadog_query(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('match_datadog_query requires 2 arguments')
	}
	obj := match args[0] {
		ObjectMap { args[0] as ObjectMap }
		else { return error('match_datadog_query requires an object as first argument') }
	}
	query := match args[1] {
		string { args[1] as string }
		else { return error('match_datadog_query requires a string query') }
	}
	node := ddq_parse(query.trim_space())!
	return VrlValue(ddq_eval(node, obj))
}

// --- Datadog query AST ---

enum DdqNodeKind {
	match_all
	match_none
	attr_exists
	attr_missing
	attr_term
	attr_phrase
	attr_prefix
	attr_wildcard
	attr_comparison
	attr_range
	negated
	boolean_and
	boolean_or
}

enum DdqCmp {
	gt
	lt
	gte
	lte
}

struct DdqNode {
	kind      DdqNodeKind
	attr      string
	value     string // for term, phrase, prefix, wildcard
	cmp       DdqCmp
	cmp_value string
	// range
	lower           string
	upper           string
	lower_inclusive  bool
	upper_inclusive  bool
	// children
	children []DdqNode
}

const ddq_default_fields = ['message', 'custom.error.message', 'custom.error.stack',
	'custom.title', '_default_']

// --- Datadog query parser ---

struct DdqParser {
	input string
mut:
	pos int
}

fn ddq_parse(query string) !DdqNode {
	if query.len == 0 {
		return DdqNode{
			kind: .match_all
		}
	}
	mut p := DdqParser{
		input: query
	}
	return p.parse_query()
}

fn (mut p DdqParser) parse_query() !DdqNode {
	mut nodes := []DdqNode{}
	mut last_conj := DdqNodeKind.boolean_and // default conjunction
	for {
		p.skip_ws()
		if p.at_end() {
			break
		}
		if p.peek() == `)` {
			break
		}
		// Check for conjunction keywords
		if p.match_keyword('AND') || p.match_str('&&') {
			last_conj = .boolean_and
			continue
		}
		if p.match_keyword('OR') || p.match_str('||') {
			last_conj = .boolean_or
			continue
		}
		// Parse clause with possible NOT/- prefix
		mut negated := false
		if p.match_keyword('NOT') {
			negated = true
			p.skip_ws()
		} else if p.peek() == `-` && !p.is_numeric_ahead() {
			p.pos++
			negated = true
			p.skip_ws()
		}
		mut clause := p.parse_clause()!
		if negated {
			clause = DdqNode{
				kind:     .negated
				children: [clause]
			}
		}
		if nodes.len > 0 && last_conj == .boolean_or {
			// Merge OR: if previous top-level is AND, wrap current in OR
			last := nodes.pop()
			nodes << DdqNode{
				kind:     .boolean_or
				children: [last, clause]
			}
		} else {
			nodes << clause
		}
		last_conj = .boolean_and
	}
	if nodes.len == 0 {
		return DdqNode{
			kind: .match_all
		}
	}
	if nodes.len == 1 {
		return nodes[0]
	}
	return DdqNode{
		kind:     .boolean_and
		children: nodes
	}
}

fn (mut p DdqParser) parse_clause() !DdqNode {
	p.skip_ws()
	// Match-all: *:*
	if p.match_str('*:*') {
		return DdqNode{
			kind: .match_all
		}
	}
	// Parenthesized subquery
	if p.peek() == `(` {
		p.pos++
		node := p.parse_query()!
		p.skip_ws()
		if !p.at_end() && p.peek() == `)` {
			p.pos++
		}
		return node
	}
	// _exists_:field
	if p.match_str('_exists_:') {
		field := p.read_term()
		return DdqNode{
			kind: .attr_exists
			attr: ddq_resolve_field(field)
		}
	}
	// _missing_:field
	if p.match_str('_missing_:') {
		field := p.read_term()
		return DdqNode{
			kind: .attr_missing
			attr: ddq_resolve_field(field)
		}
	}
	// Try field:value
	field_end := p.find_field_colon()
	if field_end >= 0 {
		raw_field := p.input[p.pos..field_end]
		p.pos = field_end + 1 // skip colon
		field := ddq_resolve_field(raw_field)
		return p.parse_value(field)
	}
	// Bare term (searches default fields)
	return p.parse_bare_term()
}

fn (mut p DdqParser) parse_value(field string) !DdqNode {
	p.skip_ws()
	if p.at_end() {
		return DdqNode{
			kind:  .attr_term
			attr:  field
			value: ''
		}
	}
	ch := p.peek()
	// Wildcard alone: *
	if ch == `*` && (p.pos + 1 >= p.input.len || p.input[p.pos + 1] in [` `, `)`, u8(0)]) {
		p.pos++
		return DdqNode{
			kind: .attr_exists
			attr: field
		}
	}
	// Parenthesized sub-query
	if ch == `(` {
		p.pos++
		node := p.parse_query()!
		p.skip_ws()
		if !p.at_end() && p.peek() == `)` {
			p.pos++
		}
		// Attach field context to leaf nodes
		return ddq_attach_field(node, field)
	}
	// Quoted phrase
	if ch == `"` {
		phrase := p.read_quoted()
		return DdqNode{
			kind:  .attr_phrase
			attr:  field
			value: phrase
		}
	}
	// Range: [lower TO upper] or {lower TO upper}
	if ch == `[` || ch == `{` {
		return p.parse_range(field)
	}
	// Comparison: >, <, >=, <=
	if ch in [`>`, `<`] {
		return p.parse_comparison(field)
	}
	// Term, possibly with wildcards or prefix
	term := p.read_term()
	if term.ends_with('*') && !term.contains('?') && term.count('*') == 1 {
		return DdqNode{
			kind:  .attr_prefix
			attr:  field
			value: ddq_unescape(term[..term.len - 1])
		}
	}
	if term.contains('*') || term.contains('?') {
		return DdqNode{
			kind:  .attr_wildcard
			attr:  field
			value: ddq_unescape(term)
		}
	}
	return DdqNode{
		kind:  .attr_term
		attr:  field
		value: ddq_unescape(term)
	}
}

fn (mut p DdqParser) parse_bare_term() !DdqNode {
	p.skip_ws()
	if p.at_end() {
		return DdqNode{
			kind: .match_all
		}
	}
	if p.peek() == `"` {
		phrase := p.read_quoted()
		return DdqNode{
			kind:  .attr_phrase
			attr:  '_default_'
			value: phrase
		}
	}
	term := p.read_term()
	if term.len == 0 {
		return DdqNode{
			kind: .match_all
		}
	}
	if term.ends_with('*') && term.count('*') == 1 && !term.contains('?') {
		return DdqNode{
			kind:  .attr_prefix
			attr:  '_default_'
			value: ddq_unescape(term[..term.len - 1])
		}
	}
	if term.contains('*') || term.contains('?') {
		return DdqNode{
			kind:  .attr_wildcard
			attr:  '_default_'
			value: ddq_unescape(term)
		}
	}
	return DdqNode{
		kind:  .attr_term
		attr:  '_default_'
		value: ddq_unescape(term)
	}
}

fn (mut p DdqParser) parse_range(field string) !DdqNode {
	lower_inclusive := p.peek() == `[`
	p.pos++ // skip [ or {
	p.skip_ws()
	lower := p.read_range_value()
	p.skip_ws()
	// Skip "TO"
	if p.match_keyword('TO') {
		p.skip_ws()
	}
	upper := p.read_range_value()
	p.skip_ws()
	upper_inclusive := if !p.at_end() && p.peek() == `]` {
		p.pos++
		true
	} else {
		if !p.at_end() && p.peek() == `}` {
			p.pos++
		}
		false
	}
	return DdqNode{
		kind:            .attr_range
		attr:            field
		lower:           lower
		upper:           upper
		lower_inclusive:  lower_inclusive
		upper_inclusive:  upper_inclusive
	}
}

fn (mut p DdqParser) parse_comparison(field string) !DdqNode {
	mut cmp := DdqCmp.gt
	if p.match_str('>=') {
		cmp = .gte
	} else if p.match_str('<=') {
		cmp = .lte
	} else if p.match_str('>') {
		cmp = .gt
	} else if p.match_str('<') {
		cmp = .lt
	}
	p.skip_ws()
	val := p.read_term()
	return DdqNode{
		kind:      .attr_comparison
		attr:      field
		cmp:       cmp
		cmp_value: ddq_unescape(val)
	}
}

// --- Parser helpers ---

fn (mut p DdqParser) skip_ws() {
	for p.pos < p.input.len && p.input[p.pos] in [` `, `\t`, `\r`, `\n`] {
		p.pos++
	}
}

fn (p DdqParser) at_end() bool {
	return p.pos >= p.input.len
}

fn (p DdqParser) peek() u8 {
	if p.pos < p.input.len {
		return p.input[p.pos]
	}
	return 0
}

fn (mut p DdqParser) match_str(s string) bool {
	if p.pos + s.len <= p.input.len && p.input[p.pos..p.pos + s.len] == s {
		p.pos += s.len
		return true
	}
	return false
}

fn (mut p DdqParser) match_keyword(kw string) bool {
	if p.pos + kw.len > p.input.len {
		return false
	}
	if p.input[p.pos..p.pos + kw.len] != kw {
		return false
	}
	// Must be followed by whitespace or end or paren
	after := p.pos + kw.len
	if after < p.input.len && p.input[after] !in [` `, `\t`, `(`, `)`, `\n`, `\r`] {
		return false
	}
	p.pos = after
	return true
}

fn (mut p DdqParser) read_term() string {
	start := p.pos
	for p.pos < p.input.len {
		ch := p.input[p.pos]
		if ch in [` `, `\t`, `)`, `]`, `}`, `\n`, `\r`] {
			break
		}
		if ch == `\\` && p.pos + 1 < p.input.len {
			p.pos += 2
			continue
		}
		p.pos++
	}
	return p.input[start..p.pos]
}

fn (mut p DdqParser) read_quoted() string {
	if p.pos < p.input.len && p.input[p.pos] == `"` {
		p.pos++
	}
	mut result := []u8{}
	for p.pos < p.input.len {
		ch := p.input[p.pos]
		if ch == `"` {
			p.pos++
			break
		}
		if ch == `\\` && p.pos + 1 < p.input.len {
			p.pos++
			result << p.input[p.pos]
			p.pos++
			continue
		}
		result << ch
		p.pos++
	}
	return result.bytestr()
}

fn (mut p DdqParser) read_range_value() string {
	// Handle quoted range values
	if p.pos < p.input.len && p.input[p.pos] == `"` {
		return p.read_quoted()
	}
	start := p.pos
	for p.pos < p.input.len {
		ch := p.input[p.pos]
		if ch in [` `, `\t`, `]`, `}`, `\n`, `\r`] {
			break
		}
		p.pos++
	}
	return p.input[start..p.pos]
}

fn (mut p DdqParser) find_field_colon() int {
	// Look ahead for a field:value pattern (field is a term followed by colon)
	mut i := p.pos
	for i < p.input.len {
		ch := p.input[i]
		if ch == `:` {
			// Check that what's before is a valid field name
			if i > p.pos {
				return i
			}
			return -1
		}
		if ch in [` `, `\t`, `(`, `)`, `"`, `[`, `]`, `{`, `}`, `\n`, `\r`] {
			return -1
		}
		if ch == `\\` {
			i += 2
			continue
		}
		i++
	}
	return -1
}

fn (p DdqParser) is_numeric_ahead() bool {
	// Check if - is followed by a digit (numeric negative, not negation)
	next := p.pos + 1
	if next < p.input.len && p.input[next] >= `0` && p.input[next] <= `9` {
		return true
	}
	return false
}

// --- Field resolution ---

fn ddq_resolve_field(raw string) string {
	// Keep the field name as-is; @ prefix is handled by matching functions
	return raw
}

fn ddq_unescape(s string) string {
	if !s.contains('\\') {
		return s
	}
	mut result := []u8{}
	mut i := 0
	for i < s.len {
		if s[i] == `\\` && i + 1 < s.len {
			i++
			result << s[i]
		} else {
			result << s[i]
		}
		i++
	}
	return result.bytestr()
}

// ddq_attach_field replaces '_default_' attr in leaf nodes with the given field.
fn ddq_attach_field(node DdqNode, field string) DdqNode {
	match node.kind {
		.attr_term, .attr_phrase, .attr_prefix, .attr_wildcard, .attr_exists, .attr_missing,
		.attr_comparison, .attr_range {
			if node.attr == '_default_' || node.attr.len == 0 {
				return DdqNode{
					...node
					attr: field
				}
			}
			return node
		}
		.negated {
			if node.children.len > 0 {
				return DdqNode{
					...node
					children: [ddq_attach_field(node.children[0], field)]
				}
			}
			return node
		}
		.boolean_and, .boolean_or {
			mut new_children := []DdqNode{}
			for child in node.children {
				new_children << ddq_attach_field(child, field)
			}
			return DdqNode{
				...node
				children: new_children
			}
		}
		.match_all, .match_none {
			return node
		}
	}
}

// --- Evaluation ---

fn ddq_eval(node DdqNode, obj ObjectMap) bool {
	match node.kind {
		.match_all { return true }
		.match_none { return false }
		.attr_exists {
			return ddq_field_exists(obj, node.attr)
		}
		.attr_missing {
			return !ddq_field_exists(obj, node.attr)
		}
		.attr_term {
			return ddq_match_term(obj, node.attr, node.value)
		}
		.attr_phrase {
			return ddq_match_term(obj, node.attr, node.value)
		}
		.attr_prefix {
			return ddq_match_prefix(obj, node.attr, node.value)
		}
		.attr_wildcard {
			return ddq_match_wildcard(obj, node.attr, node.value)
		}
		.attr_comparison {
			return ddq_match_comparison(obj, node.attr, node.cmp, node.cmp_value)
		}
		.attr_range {
			return ddq_match_range(obj, node.attr, node.lower, node.upper, node.lower_inclusive,
				node.upper_inclusive)
		}
		.negated {
			if node.children.len > 0 {
				return !ddq_eval(node.children[0], obj)
			}
			return true
		}
		.boolean_and {
			for child in node.children {
				if !ddq_eval(child, obj) {
					return false
				}
			}
			return true
		}
		.boolean_or {
			for child in node.children {
				if ddq_eval(child, obj) {
					return true
				}
			}
			return false
		}
	}
}

// --- Field access ---

// ddq_get_field resolves a dotted field path on an ObjectMap.
fn ddq_get_field(obj ObjectMap, field string) ?VrlValue {
	if field == '_default_' || field == 'message' {
		// Default field: search message, custom.error.message, custom.error.stack, custom.title
		for f in ddq_default_fields {
			if f == '_default_' {
				continue
			}
			if v := ddq_get_nested(obj, f) {
				return v
			}
		}
		return none
	}
	// Check tags array specially
	if field == 'tags' {
		return obj.get(field)
	}
	// Strip @ prefix for attribute lookups
	lookup := if field.starts_with('@') { field[1..] } else { field }
	return ddq_get_nested(obj, lookup)
}

fn ddq_get_nested(obj ObjectMap, path string) ?VrlValue {
	parts := path.split('.')
	mut current := VrlValue(obj)
	for part in parts {
		c := current
		match c {
			ObjectMap {
				current = c.get(part) or { return none }
			}
			else {
				return none
			}
		}
	}
	return current
}

fn ddq_field_exists(obj ObjectMap, field string) bool {
	if _ := ddq_get_field(obj, field) {
		return true
	}
	return false
}

// ddq_value_to_string converts a VrlValue to a string for comparison.
fn ddq_value_to_string(v VrlValue) string {
	a := v
	match a {
		string { return a }
		i64 { return a.str() }
		f64 { return a.str() }
		bool { return if a { 'true' } else { 'false' } }
		else { return '' }
	}
}

// --- Matching functions ---

fn ddq_match_term(obj ObjectMap, field string, value string) bool {
	if field == '_default_' {
		// Search default fields using substring matching
		for f in ddq_default_fields {
			if f == '_default_' {
				continue
			}
			if v := ddq_get_nested(obj, f) {
				if ddq_value_contains(v, value) {
					return true
				}
			}
		}
		return false
	}
	// Non-reserved, non-attribute fields: search within tags array
	if ddq_is_tag_field(field) {
		return ddq_match_tag(obj, field, value)
	}
	v := ddq_get_field(obj, field) or { return false }
	return ddq_value_equals(v, value)
}

// ddq_is_tag_field returns true if the field should be searched within tags.
fn ddq_is_tag_field(field string) bool {
	// @ fields are attribute paths, not tags
	if field.starts_with('@') {
		return false
	}
	// Reserved fields are NOT tags
	reserved := ['host', 'source', 'status', 'service', 'trace_id', 'message', 'timestamp',
		'tags', '_default_']
	if field in reserved {
		return false
	}
	// If the field contains dots, it's a nested attribute path, not a tag
	if field.contains('.') {
		return false
	}
	return true
}

// ddq_match_tag searches within the tags array for a tag matching field:value.
fn ddq_match_tag(obj ObjectMap, field string, value string) bool {
	tags_val := obj.get('tags') or { return false }
	tv := tags_val
	match tv {
		[]VrlValue {
			for item in tv {
				s := ddq_value_to_string(item)
				// Tags are in "key:value" format
				colon_idx := ddq_index_byte(s, `:`)
				if colon_idx >= 0 {
					tag_key := s[..colon_idx]
					tag_val := s[colon_idx + 1..]
					if tag_key.to_lower() == field.to_lower()
						&& tag_val.to_lower() == value.to_lower() {
						return true
					}
				}
			}
		}
		else {}
	}
	return false
}

fn ddq_index_byte(s string, b u8) int {
	for i := 0; i < s.len; i++ {
		if s[i] == b {
			return i
		}
	}
	return -1
}

// ddq_value_contains checks if a value contains the search term (substring match).
fn ddq_value_contains(v VrlValue, value string) bool {
	a := v
	match a {
		string {
			return a.to_lower().contains(value.to_lower())
		}
		i64 {
			return a.str() == value
		}
		f64 {
			return a.str() == value
		}
		else {
			return ddq_value_equals(v, value)
		}
	}
}

fn ddq_value_equals(v VrlValue, value string) bool {
	a := v
	match a {
		string {
			return a.to_lower() == value.to_lower()
		}
		i64 {
			return a.str() == value
		}
		f64 {
			return a.str() == value
		}
		bool {
			return (if a { 'true' } else { 'false' }) == value.to_lower()
		}
		[]VrlValue {
			for item in a {
				if ddq_value_equals(item, value) {
					return true
				}
			}
			return false
		}
		else {
			return false
		}
	}
}

fn ddq_match_prefix(obj ObjectMap, field string, prefix string) bool {
	if field == '_default_' {
		for f in ddq_default_fields {
			if f == '_default_' {
				continue
			}
			if v := ddq_get_nested(obj, f) {
				s := ddq_value_to_string(v)
				if s.to_lower().starts_with(prefix.to_lower()) {
					return true
				}
			}
		}
		return false
	}
	v := ddq_get_field(obj, field) or { return false }
	s := ddq_value_to_string(v)
	return s.to_lower().starts_with(prefix.to_lower())
}

fn ddq_match_wildcard(obj ObjectMap, field string, pattern string) bool {
	if field == '_default_' {
		for f in ddq_default_fields {
			if f == '_default_' {
				continue
			}
			if v := ddq_get_nested(obj, f) {
				s := ddq_value_to_string(v)
				if ddq_glob_match(s.to_lower(), pattern.to_lower()) {
					return true
				}
			}
		}
		return false
	}
	v := ddq_get_field(obj, field) or { return false }
	s := ddq_value_to_string(v)
	return ddq_glob_match(s.to_lower(), pattern.to_lower())
}

// ddq_glob_match matches a string against a glob pattern with * and ? wildcards.
fn ddq_glob_match(s string, pattern string) bool {
	mut si := 0
	mut pi := 0
	mut star_pi := -1
	mut star_si := -1
	for si < s.len || pi < pattern.len {
		if pi < pattern.len && pattern[pi] == `*` {
			star_pi = pi
			star_si = si
			pi++
			continue
		}
		if pi < pattern.len && si < s.len && (pattern[pi] == `?` || pattern[pi] == s[si]) {
			pi++
			si++
			continue
		}
		if star_pi >= 0 {
			pi = star_pi + 1
			star_si++
			si = star_si
			if si > s.len {
				return false
			}
			continue
		}
		return false
	}
	return true
}

fn ddq_match_comparison(obj ObjectMap, field string, cmp DdqCmp, cmp_value string) bool {
	if ddq_is_tag_field(field) {
		return ddq_match_tag_op(obj, field, fn [cmp, cmp_value] (val string) bool {
			return ddq_compare_value(VrlValue(val), cmp, cmp_value)
		})
	}
	v := ddq_get_field(obj, field) or { return false }
	return ddq_compare_value(v, cmp, cmp_value)
}

fn ddq_compare_value(v VrlValue, cmp DdqCmp, cmp_value string) bool {
	a := v
	// Try numeric comparison first
	if num := ddq_parse_number(cmp_value) {
		val_num := match a {
			i64 { f64(a) }
			f64 { a }
			string {
				ddq_parse_number(a) or { return ddq_string_compare(a, cmp, cmp_value) }
			}
			else { return false }
		}
		match cmp {
			.gt { return val_num > num }
			.lt { return val_num < num }
			.gte { return val_num >= num }
			.lte { return val_num <= num }
		}
	}
	// Fall back to string comparison
	s := ddq_value_to_string(v)
	return ddq_string_compare(s, cmp, cmp_value)
}

fn ddq_string_compare(s string, cmp DdqCmp, value string) bool {
	c := s.compare(value)
	match cmp {
		.gt { return c > 0 }
		.lt { return c < 0 }
		.gte { return c >= 0 }
		.lte { return c <= 0 }
	}
}

fn ddq_match_range(obj ObjectMap, field string, lower string, upper string, lower_incl bool, upper_incl bool) bool {
	if ddq_is_tag_field(field) {
		return ddq_match_tag_op(obj, field, fn [lower, upper, lower_incl, upper_incl] (val string) bool {
			return ddq_in_range(VrlValue(val), lower, upper, lower_incl, upper_incl)
		})
	}
	v := ddq_get_field(obj, field) or { return false }
	return ddq_in_range(v, lower, upper, lower_incl, upper_incl)
}

// ddq_match_tag_op searches tags for a matching key and applies a custom check on the value.
fn ddq_match_tag_op(obj ObjectMap, field string, check fn (string) bool) bool {
	tags_val := obj.get('tags') or { return false }
	tv := tags_val
	match tv {
		[]VrlValue {
			for item in tv {
				s := ddq_value_to_string(item)
				colon_idx := ddq_index_byte(s, `:`)
				if colon_idx >= 0 {
					tag_key := s[..colon_idx]
					tag_val := s[colon_idx + 1..]
					if tag_key.to_lower() == field.to_lower() && check(tag_val) {
						return true
					}
				}
			}
		}
		else {}
	}
	return false
}

fn ddq_in_range(v VrlValue, lower string, upper string, lower_incl bool, upper_incl bool) bool {
	a := v
	// Try numeric range
	lower_num := ddq_parse_number(lower)
	upper_num := ddq_parse_number(upper)
	val_num := match a {
		i64 { ?f64(f64(a)) }
		f64 { ?f64(a) }
		string { ddq_parse_number(a) }
		else { ?f64(none) }
	}
	if vn := val_num {
		lower_ok := if lower == '*' {
			true
		} else if ln := lower_num {
			if lower_incl { vn >= ln } else { vn > ln }
		} else {
			true
		}
		upper_ok := if upper == '*' {
			true
		} else if un := upper_num {
			if upper_incl { vn <= un } else { vn < un }
		} else {
			true
		}
		return lower_ok && upper_ok
	}
	// String range
	s := ddq_value_to_string(v)
	lower_ok := if lower == '*' {
		true
	} else {
		if lower_incl { s.compare(lower) >= 0 } else { s.compare(lower) > 0 }
	}
	upper_ok := if upper == '*' {
		true
	} else {
		if upper_incl { s.compare(upper) <= 0 } else { s.compare(upper) < 0 }
	}
	return lower_ok && upper_ok
}

fn ddq_parse_number(s string) ?f64 {
	if s == '*' {
		return none
	}
	trimmed := s.trim_space()
	if trimmed.len == 0 {
		return none
	}
	mut has_digit := false
	for i, ch in trimmed.bytes() {
		if ch >= `0` && ch <= `9` {
			has_digit = true
		} else if ch == `.` || ch == `E` || ch == `e` {
			continue
		} else if (ch == `-` || ch == `+`) && i == 0 {
			continue
		} else {
			return none
		}
	}
	if !has_digit {
		return none
	}
	return trimmed.f64()
}
