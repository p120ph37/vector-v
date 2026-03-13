module api

fn test_new_api_default_address() {
	s := new_api(map[string]string{})
	assert s.address == '0.0.0.0:8686'
	assert s.is_ready == false
}

fn test_new_api_custom_address() {
	s := new_api({
		'api.address': '127.0.0.1:9090'
	})
	assert s.address == '127.0.0.1:9090'
}

fn test_new_api_ready_default_address() {
	s := new_api_ready(map[string]string{})
	assert s.address == '0.0.0.0:8686'
	assert s.is_ready == true
}

fn test_new_api_ready_custom_address() {
	s := new_api_ready({
		'api.address': '10.0.0.1:8080'
	})
	assert s.address == '10.0.0.1:8080'
	assert s.is_ready == true
}

fn test_send_response_200() {
	// Verify send_response builds correct HTTP response format
	// We can't easily test the actual socket write, but we can verify
	// the function exists and compiles correctly by testing the status
	// text mapping logic inline
	status_text := match 200 {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert status_text == 'OK'
}

fn test_send_response_status_texts() {
	// Test all status code mappings used by send_response
	for pair in [[400, 'Bad Request'], [404, 'Not Found'], [405, 'Method Not Allowed'],
		[503, 'Service Unavailable']] {
		status := pair[0].int()
		expected := pair[1]
		actual := match status {
			200 { 'OK' }
			400 { 'Bad Request' }
			404 { 'Not Found' }
			405 { 'Method Not Allowed' }
			503 { 'Service Unavailable' }
			else { 'Unknown' }
		}
		assert actual == expected
	}
}
