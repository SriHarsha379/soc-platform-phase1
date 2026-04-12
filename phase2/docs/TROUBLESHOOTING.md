# Troubleshooting Guide

## Common Issues and Solutions

---

## Elasticsearch Issues

### 1. Elasticsearch Won't Start

**Symptom:** Container exits immediately or stays in restart loop.

**Check:**
```bash
docker-compose logs elasticsearch | tail -50
```

**Common causes and fixes:**

| Error | Fix |
|-------|-----|
| `max virtual memory areas vm.max_map_count [65530] is too low` | `sysctl -w vm.max_map_count=262144` |
| `OutOfMemoryError` on startup | Reduce heap in `jvm.options`: `-Xms2g -Xmx2g` |
| `bootstrap.memory_lock: true` error | Set `ulimit -l unlimited` or configure `memlock` in Docker compose |
| `Permission denied` on data path | `chown -R 1000:1000 /path/to/es-data` |

---

### 2. Red Cluster Status

**Symptom:** `GET /_cluster/health` returns `"status": "red"`.

**Check:**
```bash
curl -u elastic:pass localhost:9200/_cluster/health?pretty
curl -u elastic:pass localhost:9200/_cat/shards?v&h=index,shard,prirep,state,node,unassigned.reason
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Unassigned primary shards (single node + replicas) | Set `number_of_replicas: 0` for single-node dev |
| Node disconnected | Check `docker-compose ps`, restart missing node |
| Disk watermark exceeded | Free disk space or increase watermark: `cluster.routing.allocation.disk.watermark.high: 95%` |

**Quick fix for single-node dev:**
```bash
curl -u elastic:pass -X PUT localhost:9200/_settings \
  -H 'Content-Type: application/json' \
  -d '{"index.number_of_replicas": 0}'
```

---

### 3. ILM Policy Not Rolling Over

**Symptom:** Indices are not rolling over despite exceeding age/size thresholds.

**Check:**
```bash
curl -u elastic:pass localhost:9200/wazuh-alerts-*/_ilm/explain?pretty
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Write alias not set | Bootstrap index with `is_write_index: true` |
| ILM polling interval too long | `POST /_ilm/start` or wait for next poll (default: 10 min) |
| Template not applied to index | Verify template priority and recreate if needed |
| `min_age` not elapsed | Wait for the minimum age condition |

**Force immediate rollover (for testing):**
```bash
POST /wazuh-alerts/_rollover
```

---

### 4. High JVM Heap Usage

**Symptom:** Heap usage >85%, frequent GC pauses, slow queries.

**Check:**
```bash
curl -u elastic:pass localhost:9200/_nodes/stats/jvm?pretty | \
  python3 -c "import sys,json; n=json.load(sys.stdin)['nodes']; [print(f'{v[\"name\"]}: {v[\"jvm\"][\"mem\"][\"heap_used_percent\"]}%') for v in n.values()]"
```

**Fixes:**
1. Increase heap in `jvm.options` (max 31 GB)
2. Run `forcemerge` on warm indices to reduce segment count
3. Clear fielddata cache: `POST /_cache/clear?fielddata=true`
4. Check for expensive aggregations in dashboard queries

---

## Wazuh Issues

### 5. Rules Not Triggering

**Symptom:** Correlation rule events not appearing in Kibana.

**Check:**
```bash
# Test with wazuh-logtest
docker exec wazuh-manager /var/ossec/bin/wazuh-logtest
# Enter a log line and check which rules match

# Check rule loading errors
docker exec wazuh-manager /var/ossec/bin/wazuh-control status
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| XML syntax error in rule file | Run `xmllint --noout rule.xml` to validate |
| Rule file not in correct path | Check `/var/ossec/etc/rules/` directory |
| Parent rule ID wrong | Verify parent rule ID exists in Wazuh ruleset |
| Wazuh not restarted after deploy | `docker exec wazuh-manager /var/ossec/bin/wazuh-control restart` |

---

### 6. Alerts Not Appearing in Elasticsearch

**Symptom:** Wazuh is generating alerts but they don't appear in Kibana.

**Check:**
```bash
# Check Wazuh → ES integration logs
docker exec wazuh-manager cat /var/ossec/logs/integrations.log | tail -20

# Check ES index
curl -u elastic:pass localhost:9200/wazuh-alerts-*/_count
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Elasticsearch unreachable from Wazuh | Check network connectivity between containers |
| Wrong ES URL in ossec.conf | Verify `<hook_url>` in integration section |
| Index template not applied | Run `init-indices.sh` |
| Authentication error | Verify ES credentials in Wazuh config |

---

## Metrics Integration Issues

### 7. Zabbix Exporter Not Running

**Symptom:** `metrics-zabbix-*` indices empty.

**Check:**
```bash
systemctl status soc-metrics-exporter
journalctl -u soc-metrics-exporter -n 50

# Manual test run
python3 zabbix_to_es_exporter.py --config config.yaml --once
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Wrong Zabbix URL | Update `config.yaml`: `url: http://zabbix-web:8080/zabbix` |
| Wrong Zabbix credentials | Check API: `curl -X POST http://localhost:8080/zabbix/api_jsonrpc.php -d '{"jsonrpc":"2.0","method":"user.login",...}'` |
| No hosts in configured group | Add hosts to the group in Zabbix UI |
| ES connection refused | Check `elasticsearch.url` in config |

---

### 8. Missing Geo-Location Data

**Symptom:** Geographic threat map shows no data; impossible travel rule not triggering.

**Check:**
```bash
curl -u elastic:pass localhost:9200/logs-auth-*/_search \
  -H 'Content-Type: application/json' \
  -d '{"size":1,"_source":["source.ip","source.geo"]}' | python3 -m json.tool
```

**Fix:**
Enable GeoIP enrichment in Wazuh or via Elasticsearch ingest pipeline:

```json
PUT /_ingest/pipeline/geoip-enrich
{
  "processors": [{
    "geoip": {
      "field": "source.ip",
      "target_field": "source.geo",
      "ignore_missing": true
    }
  }]
}
```

---

## Kibana Issues

### 9. Dashboards Not Loading / Index Pattern Errors

**Symptom:** "No results found" or "Index pattern not found" errors.

**Fix:**
```bash
cd phase2/kibana/scripts
bash create-index-patterns.sh
bash import-dashboards.sh
```

Or manually:
1. `Stack Management → Index Patterns → Create`
2. Pattern: `wazuh-alerts-*`, Time field: `@timestamp`

---

### 10. Performance Slow Dashboard Queries

**Symptom:** Dashboard panels take > 10 seconds to load.

**Fixes:**
1. Reduce time range (use 1h or 4h instead of 7d)
2. Add host/severity filters before loading
3. Enable shard request cache: `PUT /wazuh-alerts-*/_settings {"index.requests.cache.enable": true}`
4. Check if index has been force-merged (warm phase)
5. Run `benchmark-queries.sh` to identify slow queries

---

## Logs Location Reference

| Component | Log Location |
|-----------|------------|
| Elasticsearch | `/var/log/elasticsearch/soc-platform-cluster.log` |
| Elasticsearch GC | `/var/log/elasticsearch/gc.log` |
| Wazuh Manager | `/var/ossec/logs/ossec.log` |
| Wazuh Alerts | `/var/ossec/logs/alerts/alerts.json` |
| Wazuh Integration | `/var/ossec/logs/integrations.log` |
| Kibana | `/var/log/kibana/kibana.log` |
| Zabbix Exporter | `journalctl -u soc-metrics-exporter` |

---

## Useful Commands

```bash
# ES cluster health
curl -u elastic:pass localhost:9200/_cluster/health?pretty

# ES index list
curl -u elastic:pass localhost:9200/_cat/indices?v

# ES shard allocation
curl -u elastic:pass localhost:9200/_cat/shards?v

# ILM status
curl -u elastic:pass localhost:9200/wazuh-alerts-*/_ilm/explain?pretty

# Wazuh service status
docker exec wazuh-manager /var/ossec/bin/wazuh-control status

# Restart Wazuh
docker exec wazuh-manager /var/ossec/bin/wazuh-control restart

# Test Wazuh rules
docker exec -i wazuh-manager /var/ossec/bin/wazuh-logtest

# Kibana status
curl -u elastic:pass localhost:5601/api/status | python3 -m json.tool
```
