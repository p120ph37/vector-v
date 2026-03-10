module vrl

// ObjectMap is an adaptive map that starts as flat parallel arrays for small
// sizes and promotes to a hash map when the entry count exceeds the threshold.
//
// DIVERGENCE FROM UPSTREAM: Rust VRL uses BTreeMap<KeyString, Value> for
// ObjectMap, which iterates in sorted (lexicographic) key order. Our
// implementation does NOT maintain sorted order — flat mode preserves
// approximate insertion order (swap-remove on delete can reorder), and hash
// map mode has arbitrary iteration order. This is acceptable because:
//   - JSON output (vrl_to_json) sorts keys explicitly before serializing
//   - No VRL program can observe iteration order in a way that affects
//     correctness of event processing
// If sorted iteration is ever needed internally, sort at the call site
// rather than adding overhead to every map operation.
//
// For sizes <= threshold, keys and values are stored in unsorted parallel
// arrays. Lookups use linear scan, which is fast for small sizes due to
// cache-friendly sequential memory access and no hash computation overhead.
// Inserts append in O(1) amortized, deletes use swap-remove in O(1).
//
// When size exceeds the threshold, all entries are moved into a V built-in
// map[string]VrlValue hash map. This gives O(1) amortized lookup, insert,
// and delete for large maps. Once promoted, the map stays in hash map mode
// (no demotion).
//
// Threshold of 32 was chosen as a conservative default: linear scan over
// contiguous memory reliably beats hash maps up to ~24-32 entries due to
// avoiding hash computation and bucket indirection.

const object_map_threshold = 32

pub struct ObjectMap {
pub mut:
	ks       []string
	vs       []VrlValue
	hm       map[string]VrlValue
	is_large bool
}

// new_object_map creates an empty ObjectMap in flat-array mode.
@[inline]
pub fn new_object_map() ObjectMap {
	return ObjectMap{
		ks: []string{cap: 8}
		vs: []VrlValue{cap: 8}
	}
}

// object_map_from_map creates an ObjectMap from a standard V map.
// Chooses flat or hash map mode based on size.
pub fn object_map_from_map(m map[string]VrlValue) ObjectMap {
	if m.len > object_map_threshold {
		return ObjectMap{
			hm: m.clone()
			is_large: true
		}
	}
	mut om := ObjectMap{
		ks: []string{cap: m.len}
		vs: []VrlValue{cap: m.len}
	}
	for k, v in m {
		om.ks << k
		om.vs << v
	}
	return om
}

// to_map converts this ObjectMap to a standard V map.
pub fn (om &ObjectMap) to_map() map[string]VrlValue {
	if om.is_large {
		return om.hm.clone()
	}
	mut m := map[string]VrlValue{}
	for i in 0 .. om.ks.len {
		m[om.ks[i]] = om.vs[i]
	}
	return m
}

// get returns the value for the given key, or none if not found.
@[inline]
pub fn (om &ObjectMap) get(key string) ?VrlValue {
	if om.is_large {
		if key in om.hm {
			return om.hm[key]
		}
		return none
	}
	for i in 0 .. om.ks.len {
		if om.ks[i] == key {
			return om.vs[i]
		}
	}
	return none
}

// has returns true if the key exists.
@[inline]
pub fn (om &ObjectMap) has(key string) bool {
	if om.is_large {
		return key in om.hm
	}
	for i in 0 .. om.ks.len {
		if om.ks[i] == key {
			return true
		}
	}
	return false
}

// set inserts or updates a key-value pair.
// Promotes to hash map mode if the flat arrays exceed the threshold.
@[inline]
pub fn (mut om ObjectMap) set(key string, val VrlValue) {
	if om.is_large {
		om.hm[key] = val
		return
	}
	// Linear scan for existing key
	for i in 0 .. om.ks.len {
		if om.ks[i] == key {
			om.vs[i] = val
			return
		}
	}
	// New key — append
	om.ks << key
	om.vs << val
	// Promote if over threshold
	if om.ks.len > object_map_threshold {
		om.promote()
	}
}

// delete removes a key and returns its value.
pub fn (mut om ObjectMap) delete(key string) VrlValue {
	if om.is_large {
		if key in om.hm {
			val := om.hm[key]
			om.hm.delete(key)
			return val
		}
		return VrlValue(VrlNull{})
	}
	for i in 0 .. om.ks.len {
		if om.ks[i] == key {
			val := om.vs[i]
			// Swap-remove for O(1) deletion
			last := om.ks.len - 1
			if i != last {
				om.ks[i] = om.ks[last]
				om.vs[i] = om.vs[last]
			}
			om.ks.delete_last()
			om.vs.delete_last()
			return val
		}
	}
	return VrlValue(VrlNull{})
}

// len returns the number of entries.
@[inline]
pub fn (om &ObjectMap) len() int {
	if om.is_large {
		return om.hm.len
	}
	return om.ks.len
}

// clear removes all entries and resets to flat-array mode.
pub fn (mut om ObjectMap) clear() {
	om.ks.clear()
	om.vs.clear()
	om.hm = map[string]VrlValue{}
	om.is_large = false
}

// clone_map creates a deep copy of this ObjectMap.
pub fn (om &ObjectMap) clone_map() ObjectMap {
	if om.is_large {
		return ObjectMap{
			hm: om.hm.clone()
			is_large: true
		}
	}
	return ObjectMap{
		ks: om.ks.clone()
		vs: om.vs.clone()
	}
}

// keys returns all keys as a string array.
pub fn (om &ObjectMap) keys() []string {
	if om.is_large {
		mut result := []string{cap: om.hm.len}
		for k, _ in om.hm {
			result << k
		}
		return result
	}
	return om.ks.clone()
}

// promote moves all flat-array entries into the hash map and switches mode.
fn (mut om ObjectMap) promote() {
	om.hm = map[string]VrlValue{}
	for i in 0 .. om.ks.len {
		om.hm[om.ks[i]] = om.vs[i]
	}
	om.ks.clear()
	om.vs.clear()
	om.is_large = true
}
