module vrl

fn test_sha3_256_explicit() {
	result := fn_sha3([VrlValue(''), VrlValue('SHA3-256')]) or { panic(err.msg()) }
	expected := 'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a'
	s := result as string
	assert s == expected, 'SHA3-256("") = ${s}, expected ${expected}'
}

fn test_sha3_256_abc() {
	result := fn_sha3([VrlValue('abc'), VrlValue('SHA3-256')]) or { panic(err.msg()) }
	expected := '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532'
	s := result as string
	assert s == expected, 'SHA3-256("abc") = ${s}, expected ${expected}'
}

fn test_sha3_512_default() {
	// Default variant is SHA3-512
	result := fn_sha3([VrlValue('')]) or { panic(err.msg()) }
	expected := 'a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26'
	s := result as string
	assert s == expected, 'SHA3-512("") = ${s}, expected ${expected}'
}

fn test_sha3_512_syslog_message() {
	// The conformance test uses sha3 on "syslog message"
	result := fn_sha3([VrlValue('syslog message')]) or { panic(err.msg()) }
	expected := 'f1a83003b01054c809844b19201b72d4e88cef9abe23f8323b884437a0601238b8f3895ae47eed01051660fcff7ab26461041c2237ba521de84ac1e2416271b0'
	s := result as string
	assert s == expected, 'SHA3-512("syslog message") = ${s}, expected ${expected}'
}

fn test_sha3_unknown_variant() {
	_ := fn_sha3([VrlValue(''), VrlValue('SHA3-999')]) or {
		assert err.msg() == 'unknown SHA-3 variant: SHA3-999'
		return
	}
	panic('expected error for unknown variant')
}
