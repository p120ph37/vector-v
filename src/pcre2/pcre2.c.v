module pcre2

// PCRE2 wrapper using libpcre2-8 via C interop.
// This replaces V's built-in regex.pcre module, which lacks support for
// lookahead/lookbehind assertions and atomic groups.

#define PCRE2_CODE_UNIT_WIDTH 8

// PCRE2 static linking
#flag /usr/lib/x86_64-linux-gnu/libpcre2-8.a

#include <pcre2.h>

@[typedef]
struct C.pcre2_code_8 {}

@[typedef]
struct C.pcre2_match_data_8 {}

// pcre2 C API functions
fn C.pcre2_compile_8(pattern &u8, length usize, options u32, errorcode &int, erroroffset &usize, ccontext voidptr) &C.pcre2_code_8
fn C.pcre2_code_free_8(code &C.pcre2_code_8)
fn C.pcre2_match_data_create_from_pattern_8(code &C.pcre2_code_8, gcontext voidptr) &C.pcre2_match_data_8
fn C.pcre2_match_data_free_8(match_data &C.pcre2_match_data_8)
fn C.pcre2_match_8(code &C.pcre2_code_8, subject &u8, length usize, startoffset usize, options u32, match_data &C.pcre2_match_data_8, mcontext voidptr) int
fn C.pcre2_get_ovector_pointer_8(match_data &C.pcre2_match_data_8) &usize
fn C.pcre2_get_ovector_count_8(match_data &C.pcre2_match_data_8) u32
fn C.pcre2_get_error_message_8(errorcode int, buffer &u8, bufflen usize) int
fn C.pcre2_pattern_info_8(code &C.pcre2_code_8, what u32, where_ voidptr) int

const pcre2_info_capturecount = u32(4)
const pcre2_info_namecount = u32(17)
const pcre2_info_nameentrysize = u32(18)
const pcre2_info_nametable = u32(19)
const pcre2_unset = ~usize(0) // PCRE2_UNSET is ~(PCRE2_SIZE)0

// Match holds the result of a single regex match.
pub struct Match {
pub:
	text   string
	start  int
	end    int
	groups []string
}

// Regex holds a compiled PCRE2 pattern.
pub struct Regex {
	code &C.pcre2_code_8
pub:
	pattern      string
	total_groups int
	group_names  []string // ordered by group index (0 = group 1)
}

// compile compiles a PCRE2 regex pattern.
pub fn compile(pattern string) !Regex {
	errorcode := int(0)
	erroroffset := usize(0)
	code := C.pcre2_compile_8(pattern.str, usize(pattern.len), 0, &errorcode, &erroroffset,
		unsafe { nil })
	if code == unsafe { nil } {
		mut buf := []u8{len: 256}
		C.pcre2_get_error_message_8(errorcode, buf.data, usize(buf.len))
		msg := unsafe { cstring_to_vstring(&char(buf.data)) }
		return error('regex compile error at offset ${erroroffset}: ${msg}')
	}
	// Get capture count
	capture_count := u32(0)
	C.pcre2_pattern_info_8(code, pcre2_info_capturecount, &capture_count)
	// Get named groups
	group_names := extract_group_names(code, int(capture_count))
	return Regex{
		code:         code
		pattern:      pattern
		total_groups: int(capture_count)
		group_names:  group_names
	}
}

// new_regex compiles a PCRE2 regex pattern (flags argument ignored for compatibility).
pub fn new_regex(pattern string, _ int) !Regex {
	return compile(pattern)
}

// extract_group_names reads the name table from a compiled PCRE2 pattern.
fn extract_group_names(code &C.pcre2_code_8, capture_count int) []string {
	mut names := []string{len: capture_count, init: ''}
	namecount := u32(0)
	C.pcre2_pattern_info_8(code, pcre2_info_namecount, &namecount)
	if namecount == 0 {
		return names
	}
	nameentrysize := u32(0)
	C.pcre2_pattern_info_8(code, pcre2_info_nameentrysize, &nameentrysize)
	nametable := unsafe { &u8(nil) }
	C.pcre2_pattern_info_8(code, pcre2_info_nametable, &nametable)
	for i in 0 .. int(namecount) {
		entry := unsafe { nametable + i * int(nameentrysize) }
		// First 2 bytes are the group number (big-endian)
		group_num := u32(unsafe { entry[0] }) << 8 | u32(unsafe { entry[1] })
		// Rest is the null-terminated name
		name := unsafe { cstring_to_vstring(&char(entry + 2)) }
		if group_num >= 1 && group_num <= capture_count {
			names[group_num - 1] = name
		}
	}
	return names
}

// find returns the first match in the text, or none.
pub fn (r &Regex) find(text string) ?Match {
	return r.find_from(text, 0)
}

// find_from returns the first match starting from the given byte offset.
pub fn (r &Regex) find_from(text string, start_index int) ?Match {
	match_data := C.pcre2_match_data_create_from_pattern_8(r.code, unsafe { nil })
	if match_data == unsafe { nil } {
		return none
	}
	defer {
		C.pcre2_match_data_free_8(match_data)
	}
	rc := C.pcre2_match_8(r.code, text.str, usize(text.len), usize(start_index),
		0, match_data, unsafe { nil })
	if rc < 0 {
		return none
	}
	ovector := C.pcre2_get_ovector_pointer_8(match_data)
	ov_count := int(C.pcre2_get_ovector_count_8(match_data))
	match_start := int(unsafe { ovector[0] })
	match_end := int(unsafe { ovector[1] })
	// Extract capture groups (skip group 0 which is the full match)
	mut groups := []string{cap: ov_count - 1}
	for i in 1 .. ov_count {
		gs := unsafe { ovector[i * 2] }
		ge := unsafe { ovector[i * 2 + 1] }
		if gs == pcre2_unset || ge == pcre2_unset {
			groups << ''
		} else {
			groups << text[int(gs)..int(ge)]
		}
	}
	return Match{
		text:   text[match_start..match_end]
		start:  match_start
		end:    match_end
		groups: groups
	}
}

// find_all returns all non-overlapping matches in the text.
pub fn (r &Regex) find_all(text string) []Match {
	mut matches := []Match{}
	mut pos := 0
	for pos <= text.len {
		m := r.find_from(text, pos) or { break }
		matches << m
		if m.end == m.start {
			pos = m.end + 1
		} else {
			pos = m.end
		}
	}
	return matches
}

// replace replaces the first match with the replacement string.
pub fn (r &Regex) replace(text string, repl string) string {
	m := r.find(text) or { return text }
	mut result := []u8{cap: text.len + repl.len}
	for i in 0 .. m.start {
		result << text[i]
	}
	result << repl.bytes()
	for i in m.end .. text.len {
		result << text[i]
	}
	return result.bytestr()
}

// group_by_name returns the value of the named capture group from a match.
pub fn (r &Regex) group_by_name(m Match, name string) string {
	for i, n in r.group_names {
		if n == name && i < m.groups.len {
			return m.groups[i]
		}
	}
	return ''
}

// free releases the compiled pattern. Call when done with the regex.
pub fn (r &Regex) free() {
	if r.code != unsafe { nil } {
		C.pcre2_code_free_8(r.code)
	}
}
