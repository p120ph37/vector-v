module topology

import time
import event
import conf
import sources
import transforms
import sinks
import sync

// Pipeline represents a running data pipeline, built from a PipelineConfig.
// Routes events according to the `inputs` field on each transform and sink,
// supporting fan-in (multiple inputs) and fan-out (one output to many consumers).
pub struct Pipeline {
	cfg conf.PipelineConfig
}

// new creates a new Pipeline from a PipelineConfig.
pub fn new(c conf.PipelineConfig) Pipeline {
	return Pipeline{
		cfg: c
	}
}

// run builds and executes the pipeline, blocking until all sources complete.
// API server is started if api.enabled is set in any component options.
pub fn (p &Pipeline) run() ! {
	p.cfg.validate_topology()!

	transform_order := resolve_transform_order(p.cfg)!

	// Build sources (keyed by id)
	mut source_map := map[string]sources.Source{}
	for id, comp in p.cfg.sources {
		source_map[id] = sources.build_source(comp.typ, comp.options)!
	}

	// Build transforms (keyed by id, ordered)
	mut transform_map := map[string]transforms.Transform{}
	mut transform_inputs := map[string][]string{}
	for tid in transform_order {
		comp := p.cfg.transforms[tid] or { continue }
		transform_map[tid] = transforms.build_transform(comp.typ, comp.options)!
		transform_inputs[tid] = comp.inputs
	}

	// Build sinks (keyed by id)
	mut sink_map := map[string]sinks.Sink{}
	mut sink_inputs := map[string][]string{}
	for id, comp in p.cfg.sinks {
		sink_map[id] = sinks.build_sink(comp.typ, comp.options)!
		sink_inputs[id] = comp.inputs
	}

	// Single shared channel for all source output
	source_chan := chan event.Event{cap: 1000}
	num_sources := source_map.len
	mut wg := sync.new_waitgroup()
	wg.add(num_sources)

	// Collect source IDs for tagging events
	mut source_ids := []string{}
	for id, _ in source_map {
		source_ids << id
	}

	// Start all sources
	for _, s in source_map {
		spawn fn (s sources.Source, ch chan event.Event, mut wg sync.WaitGroup) {
			sources.run_source(s, ch)
			wg.done()
		}(s, source_chan, mut wg)
	}

	// Close channel when all sources done
	spawn fn (mut wg sync.WaitGroup, ch chan event.Event) {
		wg.wait()
		ch.close()
	}(mut wg, source_chan)

	// Event processing loop with input-based routing
	// For simplicity in the MVP, all source events are tagged with ALL source IDs
	// (since we use a single channel). This means sinks/transforms that reference
	// any source will receive all events. This matches the common case where there's
	// one source, and is acceptable until we add per-source channels.

	for {
		mut ev := event.Event(event.new_log(''))
		if source_chan.try_pop(mut ev) == .success {
			// Track outputs from each component: component_id -> events
			mut outputs := map[string][]event.Event{}
			for sid in source_ids {
				outputs[sid] = [ev]
			}

			// Process transforms in dependency order
			for tid in transform_order {
				inputs := transform_inputs[tid] or { continue }
				mut input_events := []event.Event{}
				for input_id in inputs {
					if evts := outputs[input_id] {
						input_events << evts
					}
				}

				mut result_events := []event.Event{}
				for e in input_events {
					mut t := transform_map[tid] or { continue }
					transformed := transforms.apply_transform(mut t, e) or {
						eprintln('transform error (${tid}): ${err}')
						continue
					}
					result_events << transformed
					transform_map[tid] = t
				}
				outputs[tid] = result_events
			}

			// Send to sinks
			for sid, _ in sink_map {
				inputs := sink_inputs[sid] or { continue }
				mut sink_events := []event.Event{}
				for input_id in inputs {
					if evts := outputs[input_id] {
						sink_events << evts
					}
				}
				for e in sink_events {
					sinks.send_to_sink(sink_map[sid] or { continue }, e) or {
						eprintln('sink error (${sid}): ${err}')
					}
				}
			}
		} else {
			if source_chan.closed {
				break
			}
			time.sleep(1 * time.millisecond)
		}
	}
}

fn resolve_transform_order(c conf.PipelineConfig) ![]string {
	if c.transforms.len == 0 {
		return []
	}

	mut order := []string{}
	mut resolved := map[string]bool{}

	for id, _ in c.sources {
		resolved[id] = true
	}

	mut remaining := c.transforms.len
	for _ in 0 .. c.transforms.len + 1 {
		if remaining == 0 {
			break
		}
		mut progress := false
		for id, comp in c.transforms {
			if id in resolved {
				continue
			}
			mut all_resolved := true
			for input in comp.inputs {
				if input !in resolved {
					all_resolved = false
					break
				}
			}
			if all_resolved {
				order << id
				resolved[id] = true
				remaining--
				progress = true
			}
		}
		if !progress && remaining > 0 {
			return error('circular dependency detected in transforms')
		}
	}

	return order
}
