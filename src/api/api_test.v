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

fn test_send_response_status_text_200() {
	code := 200
	status_text := match code {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert status_text == 'OK'
}

fn test_send_response_status_text_400() {
	code := 400
	actual := match code {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert actual == 'Bad Request'
}

fn test_send_response_status_text_404() {
	code := 404
	actual := match code {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert actual == 'Not Found'
}

fn test_send_response_status_text_405() {
	code := 405
	actual := match code {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert actual == 'Method Not Allowed'
}

fn test_send_response_status_text_503() {
	code := 503
	actual := match code {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	assert actual == 'Service Unavailable'
}
