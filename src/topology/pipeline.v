module topology

import time
import event
import conf
import sources
import transforms
import sinks
import sync

// Pipeline represents a running data pipeline, built from a PipelineConfig.
// Wires together sources -> transforms -> sinks using channels.
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
pub fn (p &Pipeline) run() ! {
	p.cfg.validate_topology()!

	transform_order := resolve_transform_order(p.cfg)!

	mut source_list := []sources.Source{}
	for _, comp in p.cfg.sources {
		source_list << sources.build_source(comp.typ, comp.options)!
	}

	mut transform_list := []transforms.Transform{}
	for tid in transform_order {
		comp := p.cfg.transforms[tid] or { continue }
		transform_list << transforms.build_transform(comp.typ, comp.options)!
	}

	mut sink_list := []sinks.Sink{}
	for _, comp in p.cfg.sinks {
		sink_list << sinks.build_sink(comp.typ, comp.options)!
	}

	source_chan := chan event.Event{cap: 1000}
	num_sources := source_list.len
	mut wg := sync.new_waitgroup()
	wg.add(num_sources)

	// Start all sources in separate threads, close channel when all done
	for s in source_list {
		spawn fn (s sources.Source, ch chan event.Event, mut wg sync.WaitGroup) {
			sources.run_source(s, ch)
			wg.done()
		}(s, source_chan, mut wg)
	}

	// Closer thread: wait for all sources then close the channel
	spawn fn (mut wg sync.WaitGroup, ch chan event.Event) {
		wg.wait()
		ch.close()
	}(mut wg, source_chan)

	// Process events: source -> transforms -> sinks
	for {
		mut ev := event.Event(event.new_log(''))
		if source_chan.try_pop(mut ev) == .success {
			mut events := [ev]
			for mut t in transform_list {
				mut next_events := []event.Event{}
				for e in events {
					transformed := transforms.apply_transform(mut t, e) or {
						eprintln('transform error: ${err}')
						continue
					}
					next_events << transformed
				}
				events = next_events.clone()
			}

			for s in sink_list {
				for e in events {
					sinks.send_to_sink(s, e) or {
						eprintln('sink error: ${err}')
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
