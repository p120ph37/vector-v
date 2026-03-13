module vrl

import os

// parse_etld implements the VRL parse_etld() function.
// parse_etld(value, plus_parts: 0, psl: "") parses effective top-level domain info.
//
// Returns an object with:
//   etld: string          - the effective TLD
//   etld_plus: string     - the eTLD plus N additional domain labels
//   known_suffix: bool    - whether the suffix is in the official PSL

struct PslEntry {
	rule   string
	is_neg bool // negation rule (starts with !)
}

// psl_entries_cache is lazily built from psl_raw.
__global psl_entries_cache = []PslEntry{}
__global psl_entries_loaded = false

// psl_load parses the raw PSL data into structured entries.
fn psl_load() []PslEntry {
	if psl_entries_loaded {
		return psl_entries_cache
	}
	mut entries := []PslEntry{}
	for line in psl_raw.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('//') {
			continue
		}
		if trimmed.starts_with('!') {
			entries << PslEntry{
				rule:   trimmed[1..].to_lower()
				is_neg: true
			}
		} else {
			entries << PslEntry{
				rule:   trimmed.to_lower()
				is_neg: false
			}
		}
	}
	psl_entries_cache = entries.clone()
	psl_entries_loaded = true
	return entries
}

// psl_load_custom parses a custom PSL file.
// Returns an empty array if the file format is invalid.
fn psl_load_custom(data string) []PslEntry {
	mut entries := []PslEntry{}
	mut has_valid_entry := false
	for line in data.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('//') {
			continue
		}
		// Validate: PSL entries should be domain labels, not JSON/other formats
		if trimmed.contains('{') || trimmed.contains('}') || trimmed.contains('[')
			|| trimmed.contains(']') || trimmed.contains('"') || trimmed.contains(',')
			|| trimmed.contains('=') {
			return []PslEntry{} // Invalid format
		}
		if trimmed.starts_with('!') {
			entries << PslEntry{
				rule:   trimmed[1..].to_lower()
				is_neg: true
			}
			has_valid_entry = true
		} else {
			entries << PslEntry{
				rule:   trimmed.to_lower()
				is_neg: false
			}
			has_valid_entry = true
		}
	}
	if !has_valid_entry {
		return []PslEntry{}
	}
	return entries
}

// psl_lookup finds the matching PSL rule for a domain.
// Returns (suffix_labels, known) where suffix_labels is the number of labels in the eTLD.
fn psl_lookup(domain string, entries []PslEntry) (int, bool) {
	labels := domain.to_lower().split('.')
	if labels.len == 0 {
		return 1, false
	}

	mut best_match := 0
	mut best_is_neg := false
	mut found := false

	for entry in entries {
		if entry.is_neg {
			// Negation rules: if the domain matches, this overrides and the
			// effective TLD is one label shorter than the negation rule.
			if psl_match_rule(labels, entry.rule) {
				rule_labels := entry.rule.count('.') + 1
				if rule_labels > best_match || !best_is_neg {
					best_match = rule_labels
					best_is_neg = true
					found = true
				}
			}
		} else {
			if psl_match_rule(labels, entry.rule) {
				rule_labels := entry.rule.count('.') + 1
				if rule_labels > best_match && !best_is_neg {
					best_match = rule_labels
					found = true
				}
			}
		}
	}

	if best_is_neg {
		// Negation: eTLD is one label shorter than the matching negation rule
		return best_match - 1, true
	}

	if found {
		return best_match, true
	}

	// Default rule: if no rule matches, the eTLD is the last label (prevailing * rule)
	return 1, false
}

// psl_match_rule checks if domain labels match a PSL rule.
// Supports wildcard (*) in rules.
fn psl_match_rule(labels []string, rule string) bool {
	rule_parts := rule.split('.')
	if rule_parts.len > labels.len {
		return false
	}
	// Match from the right
	for i := 0; i < rule_parts.len; i++ {
		label_idx := labels.len - rule_parts.len + i
		if rule_parts[i] == '*' {
			continue // wildcard matches any label
		}
		if labels[label_idx] != rule_parts[i] {
			return false
		}
	}
	return true
}

// fn_parse_etld implements parse_etld(value, plus_parts: 0, psl: "")
fn fn_parse_etld(args []VrlValue, named_args map[string]VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_etld requires 1 argument')
	}
	domain := match args[0] {
		string { args[0] as string }
		else { return error('parse_etld requires a string argument') }
	}

	mut plus_parts := i64(0)
	if pp := named_args['plus_parts'] {
		match pp {
			i64 { plus_parts = pp }
			else { return error('parse_etld plus_parts must be an integer') }
		}
	}
	if plus_parts < 0 {
		plus_parts = 0
	}

	// Get PSL entries (default or custom)
	entries := if psl_path := named_args['psl'] {
		psl_str := match psl_path {
			string { psl_path as string }
			else { return error('parse_etld psl must be a string') }
		}
		if psl_str.len > 0 {
			// For custom PSL, read the file. Try as-is first, then relative to upstream/vrl/.
			data := read_file_string(psl_str) or {
				read_file_string('upstream/vrl/${psl_str}') or {
					return error('Unable to read psl file')
				}
			}
			custom := psl_load_custom(data)
			if custom.len == 0 {
				return error('Unable to parse psl file')
			}
			custom
		} else {
			psl_load()
		}
	} else {
		psl_load()
	}

	labels := domain.to_lower().split('.')
	if labels.len == 0 {
		return error('parse_etld: empty domain')
	}

	suffix_len, known := psl_lookup(domain, entries)

	// Extract the eTLD (last suffix_len labels)
	etld_start := if suffix_len > labels.len { 0 } else { labels.len - suffix_len }
	etld := labels[etld_start..].join('.')

	// Extract eTLD + plus_parts
	parts_to_include := suffix_len + int(plus_parts)
	plus_start := if parts_to_include > labels.len {
		0
	} else {
		labels.len - parts_to_include
	}
	etld_plus := labels[plus_start..].join('.')

	mut result := new_object_map()
	result.set('etld', VrlValue(etld))
	result.set('etld_plus', VrlValue(etld_plus))
	result.set('known_suffix', VrlValue(known))
	return VrlValue(result)
}

// read_file_string reads a file and returns its content as a string.
fn read_file_string(path string) !string {
	return os.read_file(path) or { return error(err.msg()) }
}
