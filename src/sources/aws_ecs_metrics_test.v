module sources

import os

fn test_new_ecs_metrics_defaults() {
	// Clear env to ensure default fallback
	os.unsetenv('ECS_CONTAINER_METADATA_URI_V4')

	s := new_ecs_metrics({})
	assert s.namespace == 'ecs'
	assert s.endpoint == 'http://169.254.170.2/v4'
	// Default scrape interval: 15 seconds
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_ecs_metrics_custom_endpoint() {
	s := new_ecs_metrics({
		'endpoint': 'http://localhost:51678/v4'
	})
	assert s.endpoint == 'http://localhost:51678/v4'
}

fn test_new_ecs_metrics_custom_namespace() {
	s := new_ecs_metrics({
		'namespace': 'my_ecs'
	})
	assert s.namespace == 'my_ecs'
}

fn test_new_ecs_metrics_custom_scrape_interval() {
	s := new_ecs_metrics({
		'scrape_interval_secs': '30'
	})
	// 30 seconds in nanoseconds
	assert s.scrape_interval == 30_000_000_000
}

fn test_new_ecs_metrics_negative_scrape_interval() {
	s := new_ecs_metrics({
		'scrape_interval_secs': '-5'
	})
	// Falls back to 15 seconds default
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_ecs_metrics_zero_scrape_interval() {
	s := new_ecs_metrics({
		'scrape_interval_secs': '0'
	})
	// Falls back to 15 seconds default
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_ecs_metrics_env_endpoint() {
	os.setenv('ECS_CONTAINER_METADATA_URI_V4', 'http://169.254.170.2/v4/custom', true)
	defer { os.unsetenv('ECS_CONTAINER_METADATA_URI_V4') }

	s := new_ecs_metrics({})
	assert s.endpoint == 'http://169.254.170.2/v4/custom'
}

fn test_new_ecs_metrics_explicit_endpoint_overrides_env() {
	os.setenv('ECS_CONTAINER_METADATA_URI_V4', 'http://from-env/v4', true)
	defer { os.unsetenv('ECS_CONTAINER_METADATA_URI_V4') }

	s := new_ecs_metrics({
		'endpoint': 'http://explicit/v4'
	})
	assert s.endpoint == 'http://explicit/v4'
}

fn test_new_ecs_metrics_all_options() {
	s := new_ecs_metrics({
		'endpoint':             'http://localhost:9999/v4'
		'namespace':            'custom_ns'
		'scrape_interval_secs': '60'
	})
	assert s.endpoint == 'http://localhost:9999/v4'
	assert s.namespace == 'custom_ns'
	assert s.scrape_interval == 60_000_000_000
}

fn test_ecs_metrics_registry() {
	s := build_source('aws_ecs_metrics', {}) or { panic(err.str()) }
	assert s is EcsMetricsSource
}

fn test_ecs_metrics_registry_with_config() {
	s := build_source('aws_ecs_metrics', {
		'namespace': 'test_ecs'
		'endpoint':  'http://localhost:1234/v4'
	}) or { panic(err.str()) }
	assert s is EcsMetricsSource
}
