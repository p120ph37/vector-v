module transforms

import event

// passthrough is the simplest transform - it passes events through unchanged.
pub fn passthrough(e event.Event) ![]event.Event {
	return [e]
}
