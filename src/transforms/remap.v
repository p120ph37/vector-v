module transforms

import event

// RemapTransform applies VRL-like field manipulation to events.
// This is a simplified initial implementation that supports basic operations:
//   - Setting fields: .field = "value"
//   - Deleting fields: del(.field)
//   - Renaming: .new_field = .old_field; del(.old_field)
//
// Full VRL support will be added incrementally.
// Mirrors Vector's remap transform (src/transforms/remap.rs).
pub struct RemapTransform {
	source string // The VRL source code
	ops    []RemapOp
}

// RemapOp represents a single remap operation.
type RemapOp = SetFieldOp | DeleteFieldOp

struct SetFieldOp {
	field string
	value RemapValue
}

struct DeleteFieldOp {
	field string
}

type RemapValue = StaticString | FieldRef

struct StaticString {
	val string
}

struct FieldRef {
	field string
}

// new_remap creates a new RemapTransform by parsing a simple VRL-like source.
pub fn new_remap(opts map[string]string) !RemapTransform {
	source := opts['source'] or { return error('remap transform requires "source" option') }

	mut ops := []RemapOp{}

	lines := source.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}

		// Handle del(.field)
		if trimmed.starts_with('del(') && trimmed.ends_with(')') {
			field_ref := trimmed[4..trimmed.len - 1].trim_space()
			if field_ref.starts_with('.') {
				ops << RemapOp(DeleteFieldOp{
					field: field_ref[1..]
				})
				continue
			}
		}

		// Handle .field = "value" or .field = .other_field
		eq_pos := trimmed.index_u8(`=`)
		if eq_pos > 0 {
			lhs := trimmed[..eq_pos].trim_space()
			rhs := trimmed[eq_pos + 1..].trim_space()

			if lhs.starts_with('.') {
				target_field := lhs[1..]
				// Check if RHS is a field reference
				if rhs.starts_with('.') {
					ops << RemapOp(SetFieldOp{
						field: target_field
						value: RemapValue(FieldRef{
							field: rhs[1..]
						})
					})
				} else {
					// Static string value (strip quotes)
					val := if rhs.len >= 2
						&& ((rhs[0] == `"` && rhs[rhs.len - 1] == `"`)
						|| (rhs[0] == `'` && rhs[rhs.len - 1] == `'`)) {
						rhs[1..rhs.len - 1]
					} else {
						rhs
					}
					ops << RemapOp(SetFieldOp{
						field: target_field
						value: RemapValue(StaticString{
							val: val
						})
					})
				}
			}
		}
	}

	return RemapTransform{
		source: source
		ops: ops
	}
}

// transform applies the remap operations to an event.
pub fn (t &RemapTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			mut log := e
			for op in t.ops {
				match op {
					SetFieldOp {
						val := match op.value {
							StaticString {
								event.Value(op.value.val)
							}
							FieldRef {
								log.get(op.value.field) or { event.Value('') }
							}
						}
						log.set(op.field, val)
					}
					DeleteFieldOp {
						log.remove(op.field)
					}
				}
			}
			return [event.Event(log)]
		}
		else {
			// Pass non-log events through unchanged
			return [e]
		}
	}
}
