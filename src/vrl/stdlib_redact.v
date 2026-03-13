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

// match_datadog_query(value, query) - matches an object against a Datadog query
fn fn_match_datadog_query(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('match_datadog_query requires 2 arguments')
	}
	obj := args[0]
	query_val := args[1]
	query := match query_val {
		string { query_val }
		else { return error('match_datadog_query requires a string query') }
	}
	if query.starts_with('@') {
		colon := query.index(':') or {
			return error('invalid datadog query: missing colon')
		}
		field := query[1..colon]
		value := query[colon + 1..]
		match obj {
			ObjectMap {
				if v := obj.get(field) {
					match v {
						i64 {
							if value == v.str() {
								return VrlValue(true)
							}
						}
						f64 {
							if value == v.str() {
								return VrlValue(true)
							}
						}
						string {
							if value == v {
								return VrlValue(true)
							}
						}
						else {}
					}
					return VrlValue(false)
				}
				return VrlValue(false)
			}
			else {
				return error('match_datadog_query requires an object')
			}
		}
	}
	return VrlValue(false)
}
