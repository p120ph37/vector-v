module transforms

import event
import vrl

// RemapTransform applies VRL programs to events.
// Mirrors Vector's remap transform (src/transforms/remap.rs).
pub struct RemapTransform {
	source string // The VRL source code
}

// new_remap creates a new RemapTransform.
pub fn new_remap(opts map[string]string) !RemapTransform {
	source := opts['source'] or { return error('remap transform requires "source" option') }
	return RemapTransform{
		source: source
	}
}

// transform applies the VRL program to an event.
pub fn (t &RemapTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			// Convert event fields to VRL values
			mut vrl_obj := map[string]vrl.VrlValue{}
			for k, v in e.fields {
				vrl_obj[k] = event_value_to_vrl(v)
			}

			// Compile VRL program
			mut lex := vrl.new_lexer(t.source)
			tokens := lex.tokenize()
			mut parser := vrl.new_parser(tokens)
			ast := parser.parse()!

			// Execute and get modified object
			mut rt := vrl.new_runtime_with_object(vrl_obj)
			rt.eval(ast) or {
				return error('VRL execution error: ${err}')
			}

			// Read back the modified object from the runtime
			obj := rt.get_object()

			mut log := event.LogEvent{
				fields: map[string]event.Value{}
				meta: e.meta
			}
			for k, v in obj {
				log.fields[k] = vrl_value_to_event(v)
			}
			return [event.Event(log)]
		}
		else {
			return [e]
		}
	}
}

// event_value_to_vrl converts an event.Value to a vrl.VrlValue.
fn event_value_to_vrl(v event.Value) vrl.VrlValue {
	match v {
		string { return vrl.VrlValue(v) }
		int { return vrl.VrlValue(v) }
		event.Float { return vrl.VrlValue(f64(v)) }
		bool { return vrl.VrlValue(v) }
		[]event.Value {
			mut items := []vrl.VrlValue{}
			for item in v {
				items << event_value_to_vrl(item)
			}
			return vrl.VrlValue(items)
		}
		map[string]event.Value {
			mut obj := map[string]vrl.VrlValue{}
			for k, val in v {
				obj[k] = event_value_to_vrl(val)
			}
			return vrl.VrlValue(obj)
		}
		else {
			return vrl.VrlValue(vrl.VrlNull{})
		}
	}
}

// vrl_value_to_event converts a vrl.VrlValue to an event.Value.
fn vrl_value_to_event(v vrl.VrlValue) event.Value {
	match v {
		string { return event.Value(v) }
		int { return event.Value(v) }
		f64 { return event.Value(event.Float(v)) }
		bool { return event.Value(v) }
		[]vrl.VrlValue {
			mut items := []event.Value{}
			for item in v {
				items << vrl_value_to_event(item)
			}
			return event.Value(items)
		}
		map[string]vrl.VrlValue {
			mut obj := map[string]event.Value{}
			for k, val in v {
				obj[k] = vrl_value_to_event(val)
			}
			return event.Value(obj)
		}
		else {
			// VrlNull, Timestamp, VrlRegex → convert to string
			return event.Value('')
		}
	}
}
