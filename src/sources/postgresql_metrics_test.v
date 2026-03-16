module sources

import event

fn test_parse_postgresql_uri_full() {
	ep := parse_postgresql_uri('postgres://myuser:mypass@db.example.com:5432/mydb')
	assert ep.user == 'myuser'
	assert ep.password == 'mypass'
	assert ep.host == 'db.example.com'
	assert ep.port == 5432
	assert ep.database == 'mydb'
}

fn test_parse_postgresql_uri_no_password() {
	ep := parse_postgresql_uri('postgres://admin@localhost:5432/app')
	assert ep.user == 'admin'
	assert ep.password == ''
	assert ep.host == 'localhost'
	assert ep.port == 5432
	assert ep.database == 'app'
}

fn test_parse_postgresql_uri_default_port() {
	ep := parse_postgresql_uri('postgres://user:pass@host/db')
	assert ep.host == 'host'
	assert ep.port == 5432
	assert ep.database == 'db'
}

fn test_parse_postgresql_uri_no_database() {
	ep := parse_postgresql_uri('postgres://user:pass@host:5433')
	assert ep.user == 'user'
	assert ep.password == 'pass'
	assert ep.host == 'host'
	assert ep.port == 5433
	assert ep.database == ''
}

fn test_parse_postgresql_uri_postgresql_scheme() {
	ep := parse_postgresql_uri('postgresql://user:pass@host:5432/db')
	assert ep.user == 'user'
	assert ep.host == 'host'
	assert ep.database == 'db'
}

fn test_parse_postgresql_uri_with_query_params() {
	ep := parse_postgresql_uri('postgres://user:pass@host:5432/db?sslmode=require&connect_timeout=10')
	assert ep.database == 'db'
	assert ep.host == 'host'
}

fn test_parse_postgresql_uri_localhost_only() {
	ep := parse_postgresql_uri('postgres://localhost')
	assert ep.host == 'localhost'
	assert ep.port == 5432
}

fn test_build_pg_stat_database_metrics_basic() {
	stats := {
		'connections':              '10'
		'transactions_committed':   '1000'
		'transactions_rolled_back': '5'
		'blks_read':               '5000'
		'blks_hit':                '95000'
		'tup_returned':            '50000'
		'tup_fetched':             '25000'
		'tup_inserted':            '1000'
		'tup_updated':             '500'
		'tup_deleted':             '100'
	}
	metrics := build_pg_stat_database_metrics('postgresql', 'db.local:5432', 'mydb', stats)
	assert metrics.len == 10

	// Verify connections metric
	conn_metric := metrics[0]
	assert conn_metric.name == 'postgresql_connections'
	assert conn_metric.tags['server'] == 'db.local:5432'
	assert conn_metric.tags['db'] == 'mydb'
	assert conn_metric.meta.source_type == 'postgresql_metrics'
	val := conn_metric.value
	match val {
		event.GaugeValue {
			assert val.value == 10.0
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_build_pg_stat_database_metrics_committed() {
	stats := {
		'transactions_committed': '42'
	}
	metrics := build_pg_stat_database_metrics('pg', 'host:5432', 'testdb', stats)
	assert metrics.len == 1
	assert metrics[0].name == 'pg_transactions_committed'
	val := metrics[0].value
	match val {
		event.GaugeValue {
			assert val.value == 42.0
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_build_pg_stat_database_metrics_partial_stats() {
	stats := {
		'blks_read':    '100'
		'blks_hit':     '900'
		'tup_returned': '500'
	}
	metrics := build_pg_stat_database_metrics('postgresql', 'server:5432', 'db', stats)
	assert metrics.len == 3
	names := metrics.map(it.name)
	assert 'postgresql_blks_read' in names
	assert 'postgresql_blks_hit' in names
	assert 'postgresql_tup_returned' in names
}

fn test_build_pg_stat_database_metrics_empty_stats() {
	stats := map[string]string{}
	metrics := build_pg_stat_database_metrics('postgresql', 'server:5432', 'db', stats)
	assert metrics.len == 0
}

fn test_build_pg_stat_database_metrics_custom_namespace() {
	stats := {
		'connections': '5'
	}
	metrics := build_pg_stat_database_metrics('custom_ns', 'host:5432', 'db', stats)
	assert metrics.len == 1
	assert metrics[0].name == 'custom_ns_connections'
}

fn test_build_pg_stat_database_metrics_tags() {
	stats := {
		'tup_inserted': '100'
		'tup_updated':  '50'
		'tup_deleted':  '25'
	}
	metrics := build_pg_stat_database_metrics('postgresql', 'pg.prod:5432', 'orders', stats)
	for m in metrics {
		assert m.tags['server'] == 'pg.prod:5432'
		assert m.tags['db'] == 'orders'
	}
}

fn test_parse_pg_stat_row_basic() {
	row := parse_pg_stat_row('connections=10 | transactions_committed=100 | blks_read=50')
	assert row['connections'] == '10'
	assert row['transactions_committed'] == '100'
	assert row['blks_read'] == '50'
}

fn test_parse_pg_stat_row_empty() {
	row := parse_pg_stat_row('')
	assert row.len == 0
}

fn test_parse_pg_stat_row_single() {
	row := parse_pg_stat_row('connections=42')
	assert row['connections'] == '42'
}

fn test_new_postgresql_metrics_defaults() {
	s := new_postgresql_metrics(map[string]string{})
	assert s.endpoints.len == 0
	assert s.scrape_interval_secs == 15
	assert s.namespace == 'postgresql'
}

fn test_new_postgresql_metrics_custom() {
	s := new_postgresql_metrics({
		'endpoints':            'postgres://user:pass@host1:5432/db1,postgres://user:pass@host2:5433/db2'
		'scrape_interval_secs': '30'
		'namespace':            'pg'
	})
	assert s.endpoints.len == 2
	assert s.endpoints[0].host == 'host1'
	assert s.endpoints[0].port == 5432
	assert s.endpoints[0].database == 'db1'
	assert s.endpoints[1].host == 'host2'
	assert s.endpoints[1].port == 5433
	assert s.endpoints[1].database == 'db2'
	assert s.scrape_interval_secs == 30
	assert s.namespace == 'pg'
}

fn test_new_postgresql_metrics_invalid_interval() {
	s := new_postgresql_metrics({
		'scrape_interval_secs': '0'
	})
	assert s.scrape_interval_secs == 15
}

fn test_build_pg_stat_database_metrics_float_values() {
	stats := {
		'connections': '3.14'
	}
	metrics := build_pg_stat_database_metrics('postgresql', 'host:5432', 'db', stats)
	assert metrics.len == 1
	val := metrics[0].value
	match val {
		event.GaugeValue {
			assert val.value > 3.1 && val.value < 3.2
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_postgresql_metrics_source_registry() {
	s := build_source('postgresql_metrics', map[string]string{}) or { panic(err.str()) }
	assert s is PostgresqlMetricsSource
}
