module vrl

// chunks(value, chunk_size) - split into chunks
fn fn_chunks(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('chunks requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	chunk_size := match a1 {
		i64 { a1 }
		else { return error('chunks second arg must be integer') }
	}
	if chunk_size < 1 {
		return error('"chunk_size" must be at least 1 byte')
	}
	match a0 {
		string {
			mut result := []VrlValue{}
			mut i := 0
			for i < a0.len {
				end := if i + int(chunk_size) > a0.len { a0.len } else { i + int(chunk_size) }
				result << VrlValue(a0[i..end])
				i = end
			}
			return VrlValue(result)
		}
		[]VrlValue {
			mut result := []VrlValue{}
			mut i := 0
			for i < a0.len {
				end := if i + int(chunk_size) > a0.len { a0.len } else { i + int(chunk_size) }
				result << VrlValue(a0[i..end])
				i = end
			}
			return VrlValue(result)
		}
		else {
			return error('chunks requires a string or array')
		}
	}
}
