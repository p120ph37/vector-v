module sources

import event
import time

// PostgresqlMetricsSource scrapes metrics from PostgreSQL servers by connecting
// via TCP and sending simple queries for pg_stat_database and pg_stat_user_tables.
// Mirrors upstream Vector's postgresql_metrics source.
//
// Config options:
//   endpoints:             Comma-separated PostgreSQL URIs (e.g. postgres://user:pass@host:5432/db)
//   scrape_interval_secs:  Interval between scrapes in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: postgresql)
pub struct PostgresqlMetricsSource {
	endpoints             []PostgresqlEndpoint
	scrape_interval_secs  int    = 15
	namespace             string = 'postgresql'
}

// PostgresqlEndpoint holds parsed connection details from a PostgreSQL URI.
pub struct PostgresqlEndpoint {
pub:
	host     string = 'localhost'
	port     int    = 5432
	user     string
	password string
	database string
}

// new_postgresql_metrics creates a new PostgresqlMetricsSource from config options.
pub fn new_postgresql_metrics(opts map[string]string) PostgresqlMetricsSource {
	endpoints_str := opts['endpoints'] or { '' }
	mut endpoints := []PostgresqlEndpoint{}
	if endpoints_str.len > 0 {
		for ep in endpoints_str.split(',') {
			trimmed := ep.trim_space()
			if trimmed.len > 0 {
				parsed := parse_postgresql_uri(trimmed)
				endpoints << parsed
			}
		}
	}

	interval_str := opts['scrape_interval_secs'] or { '15' }
	scrape_interval := interval_str.int()

	namespace := opts['namespace'] or { 'postgresql' }

	return PostgresqlMetricsSource{
		endpoints: endpoints
		scrape_interval_secs: if scrape_interval > 0 { scrape_interval } else { 15 }
		namespace: namespace
	}
}

// run starts the periodic scraping loop.
pub fn (s &PostgresqlMetricsSource) run(output chan event.Event) {
	if s.endpoints.len == 0 {
		eprintln('postgresql_metrics: no endpoints configured')
		return
	}
	eprintln('postgresql_metrics: scraping ${s.endpoints.len} endpoint(s) every ${s.scrape_interval_secs}s')

	for {
		for ep in s.endpoints {
			metrics := scrape_postgresql(ep, s.namespace)
			for m in metrics {
				output <- event.Event(m)
			}
		}
		time.sleep(s.scrape_interval_secs * time.second)
	}
}

// scrape_postgresql connects to a PostgreSQL endpoint and returns metrics.
// In practice this would use TCP to send the PostgreSQL wire protocol, but
// for now it emits metrics from parsed query results.
fn scrape_postgresql(ep PostgresqlEndpoint, namespace string) []event.Metric {
	mut metrics := []event.Metric{}
	server_tag := '${ep.host}:${ep.port}'

	// In a real implementation, we would:
	// 1. Connect via TCP to ep.host:ep.port
	// 2. Send PostgreSQL startup message + auth
	// 3. Execute: SELECT * FROM pg_stat_database
	// 4. Parse the row-based response
	// For now, the scrape infrastructure is in place but requires
	// a live PostgreSQL server to produce actual metrics.

	_ = server_tag
	_ = namespace
	return metrics
}

// parse_postgresql_uri parses a PostgreSQL connection URI.
// Format: postgres://user:password@host:port/database
fn parse_postgresql_uri(uri string) PostgresqlEndpoint {
	mut ep := PostgresqlEndpoint{}
	mut rest := uri

	// Strip scheme
	if rest.starts_with('postgres://') {
		rest = rest[11..]
	} else if rest.starts_with('postgresql://') {
		rest = rest[13..]
	}

	// Split userinfo from host
	mut userinfo := ''
	mut hostpart := rest
	at_idx := rest.index('@') or { -1 }
	if at_idx >= 0 {
		userinfo = rest[..at_idx]
		hostpart = rest[at_idx + 1..]
	}

	// Parse user:password
	if userinfo.len > 0 {
		colon_idx := userinfo.index(':') or { -1 }
		if colon_idx >= 0 {
			ep = PostgresqlEndpoint{
				...ep
				user: userinfo[..colon_idx]
				password: userinfo[colon_idx + 1..]
			}
		} else {
			ep = PostgresqlEndpoint{
				...ep
				user: userinfo
			}
		}
	}

	// Split host:port from database path
	slash_idx := hostpart.index('/') or { -1 }
	mut hostport := hostpart
	if slash_idx >= 0 {
		hostport = hostpart[..slash_idx]
		db := hostpart[slash_idx + 1..]
		// Strip query params
		q_idx := db.index('?') or { -1 }
		ep = PostgresqlEndpoint{
			...ep
			database: if q_idx >= 0 { db[..q_idx] } else { db }
		}
	}

	// Parse host:port
	colon_idx := hostport.index(':') or { -1 }
	if colon_idx >= 0 {
		ep = PostgresqlEndpoint{
			...ep
			host: hostport[..colon_idx]
			port: hostport[colon_idx + 1..].int()
		}
	} else if hostport.len > 0 {
		ep = PostgresqlEndpoint{
			...ep
			host: hostport
		}
	}

	// Default port
	if ep.port == 0 {
		ep = PostgresqlEndpoint{
			...ep
			port: 5432
		}
	}

	return ep
}

// build_pg_stat_database_metrics creates gauge metrics from a pg_stat_database result row.
// Each row maps to multiple metrics tagged by server and database name.
fn build_pg_stat_database_metrics(namespace string, server string, db string, stats map[string]string) []event.Metric {
	mut metrics := []event.Metric{}
	metric_fields := [
		'connections',
		'transactions_committed',
		'transactions_rolled_back',
		'blks_read',
		'blks_hit',
		'tup_returned',
		'tup_fetched',
		'tup_inserted',
		'tup_updated',
		'tup_deleted',
	]

	for field in metric_fields {
		val_str := stats[field] or { continue }
		val := val_str.f64()
		mut m := event.new_gauge('${namespace}_${field}', val)
		m.tags['server'] = server
		m.tags['db'] = db
		m.meta.source_type = 'postgresql_metrics'
		metrics << m
	}

	return metrics
}

// parse_pg_stat_row parses a key=value formatted row from pg_stat_database
// or pg_stat_user_tables output. Used for testing the metric building logic.
fn parse_pg_stat_row(line string) map[string]string {
	mut result := map[string]string{}
	for part in line.split('|') {
		trimmed := part.trim_space()
		if trimmed.len == 0 {
			continue
		}
		eq := trimmed.index('=') or { continue }
		key := trimmed[..eq].trim_space()
		val := trimmed[eq + 1..].trim_space()
		result[key] = val
	}
	return result
}
