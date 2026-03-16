# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (5 not implemented)
| Source | Notes |
|--------|-------|
| apache_metrics | Prometheus scrape of Apache mod_status |
| dnstap | DNS tap protocol |
| eventstoredb_metrics | EventStoreDB stats |
| mongodb_metrics | MongoDB server stats |
| nginx_metrics | Nginx stub_status metrics |
| okta | Okta system log API |

### Transforms (1 not implemented)
| Transform | Notes |
|-----------|-------|
| lua | Lua scripting (V has no Lua FFI) |

### Sinks (18+ not implemented)
Major categories not yet implemented:
- **Azure**: blob, logs_ingestion, monitor_logs
- **GCP**: Cloud Storage, Chronicle, Stackdriver
- **Databases**: clickhouse, elasticsearch, postgres, influxdb, greptimedb, databend, doris
- **Observability**: new_relic, honeycomb, sematext, axiom, appsignal, humio
- **Other**: webhdfs
