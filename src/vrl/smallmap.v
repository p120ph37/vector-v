module vrl

// SmallMap is a flat-array map optimized for small key counts (1-16 keys),
// which is the typical size of Vector event objects.
//
// For small maps, linear scan over contiguous memory beats hash map lookup
// because: no hash computation, no bucket indirection, cache-friendly
// sequential access, and lower memory overhead (two arrays vs hash table
// with buckets and metadata).
//
// Rust's BTreeMap achieves similar benefits for small sizes by storing
// entries in a single sorted node. This is our V equivalent.
pub struct SmallMap {
mut:
	ks []string
	vs []VrlValue
}

// new_small_map creates an empty SmallMap.
@[inline]
pub fn new_small_map() SmallMap {
	return SmallMap{
		ks: []string{cap: 8}
		vs: []VrlValue{cap: 8}
	}
}

// from_map creates a SmallMap from a standard V map.
pub fn small_map_from_map(m map[string]VrlValue) SmallMap {
	mut sm := SmallMap{
		ks: []string{cap: m.len}
		vs: []VrlValue{cap: m.len}
	}
	for k, v in m {
		sm.ks << k
		sm.vs << v
	}
	return sm
}

// to_map converts this SmallMap to a standard V map.
pub fn (sm &SmallMap) to_map() map[string]VrlValue {
	mut m := map[string]VrlValue{}
	for i in 0 .. sm.ks.len {
		m[sm.ks[i]] = sm.vs[i]
	}
	return m
}

// get returns the value for the given key, or none if not found.
@[inline]
pub fn (sm &SmallMap) get(key string) ?VrlValue {
	for i in 0 .. sm.ks.len {
		if sm.ks[i] == key {
			return sm.vs[i]
		}
	}
	return none
}

// has returns true if the key exists.
@[inline]
pub fn (sm &SmallMap) has(key string) bool {
	for i in 0 .. sm.ks.len {
		if sm.ks[i] == key {
			return true
		}
	}
	return false
}

// set inserts or updates a key-value pair.
@[inline]
pub fn (mut sm SmallMap) set(key string, val VrlValue) {
	for i in 0 .. sm.ks.len {
		if sm.ks[i] == key {
			sm.vs[i] = val
			return
		}
	}
	sm.ks << key
	sm.vs << val
}

// delete removes a key and returns its value.
pub fn (mut sm SmallMap) delete(key string) VrlValue {
	for i in 0 .. sm.ks.len {
		if sm.ks[i] == key {
			val := sm.vs[i]
			// Swap-remove for O(1) deletion
			last := sm.ks.len - 1
			if i != last {
				sm.ks[i] = sm.ks[last]
				sm.vs[i] = sm.vs[last]
			}
			sm.ks.delete_last()
			sm.vs.delete_last()
			return val
		}
	}
	return VrlValue(VrlNull{})
}

// len returns the number of entries.
@[inline]
pub fn (sm &SmallMap) len() int {
	return sm.ks.len
}

// clear removes all entries.
pub fn (mut sm SmallMap) clear() {
	sm.ks.clear()
	sm.vs.clear()
}

// clone creates a copy of this SmallMap.
pub fn (sm &SmallMap) clone_map() SmallMap {
	return SmallMap{
		ks: sm.ks.clone()
		vs: sm.vs.clone()
	}
}
