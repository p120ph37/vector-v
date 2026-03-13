module transforms

import event

// Transform is a tagged union of all transform types.
pub type Transform = RemapTransform
	| FilterTransform
	| ReduceTransform
	| Ec2MetadataTransform
	| DedupeTransform
	| SampleTransform
	| ThrottleTransform
	| ExclusiveRouteTransform

// build_transform creates a Transform from a type name and config options.
pub fn build_transform(typ string, opts map[string]string) !Transform {
	match typ {
		'remap' {
			return Transform(new_remap(opts)!)
		}
		'filter' {
			return Transform(new_filter(opts)!)
		}
		'reduce' {
			return Transform(new_reduce(opts)!)
		}
		'aws_ec2_metadata' {
			return Transform(new_ec2_metadata(opts)!)
		}
		'dedupe' {
			return Transform(new_dedupe(opts)!)
		}
		'sample' {
			return Transform(new_sample(opts)!)
		}
		'throttle' {
			return Transform(new_throttle(opts)!)
		}
		'exclusive_route' {
			return Transform(new_exclusive_route(opts)!)
		}
		else {
			return error('unknown transform type: "${typ}"')
		}
	}
}

// apply_transform dispatches an event through the appropriate transform.
pub fn apply_transform(mut t Transform, e event.Event) ![]event.Event {
	match mut t {
		RemapTransform {
			return t.transform(e)
		}
		FilterTransform {
			return t.transform(e)
		}
		ReduceTransform {
			return t.transform(e)
		}
		Ec2MetadataTransform {
			return t.transform(e)
		}
		DedupeTransform {
			return t.transform(e)
		}
		SampleTransform {
			return t.transform(e)
		}
		ThrottleTransform {
			return t.transform(e)
		}
		ExclusiveRouteTransform {
			return t.transform(e)
		}
	}
}
