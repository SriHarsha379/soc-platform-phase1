# Query Optimization Guide

## Elasticsearch Performance Tuning for SOC Queries

This guide covers query patterns, caching strategies, and optimization techniques to achieve the Phase 2 target of **< 5 second query response times**.

---

## General Principles

### 1. Always Filter by @timestamp First

Time-range filters enable **shard elimination** — ES skips shards where all data is outside the range.

```json
// GOOD: timestamp filter in filter context (cached, no scoring)
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "@timestamp": { "gte": "now-1h" } } },
        { "term": { "host.name": "web-server-01" } }
      ]
    }
  }
}

// BAD: no timestamp filter — scans all shards
{
  "query": {
    "term": { "host.name": "web-server-01" }
  }
}
```

### 2. Use `filter` vs `must` for Non-Scoring Queries

`filter` context is **cached** and avoids relevance scoring overhead.

```json
// GOOD: use filter for exact match conditions
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "event.outcome": "failure" } },
        { "term": { "event.category": "authentication" } }
      ]
    }
  }
}

// BAD for aggregations: must context scores every document
{
  "query": {
    "bool": {
      "must": [
        { "match": { "event.outcome": "failure" } }
      ]
    }
  }
}
```

### 3. Prefer `term`/`terms` Over `match` for Known Values

`match` is for full-text search and runs through the analysis chain. For exact keyword values, use `term`.

```json
// GOOD: exact keyword match
{ "term": { "rule.groups": "brute-force" } }

// LESS EFFICIENT for exact values: runs through analyzer
{ "match": { "rule.groups": "brute-force" } }
```

### 4. Avoid `wildcard` Queries on Large Indices

Wildcards scan all terms in the inverted index. Prefer prefix queries or redesign the field.

```json
// GOOD: use prefix query
{ "prefix": { "user.name": "svc-" } }

// SLOW: wildcard scans all terms
{ "wildcard": { "user.name": "svc-*" } }

// BETTER: use a dedicated field for service account flag
{ "term": { "labels.account_type": "service" } }
```

---

## Aggregation Optimization

### Size and Shard-Level Reduction

```json
{
  "size": 0,              // Don't return hits, only aggregations
  "aggs": {
    "by_host": {
      "terms": {
        "field": "host.name",
        "size": 10,        // Limit to top 10
        "shard_size": 50   // Collect 50 per shard for accuracy
      }
    }
  }
}
```

### Use `composite` Aggregations for Pagination

```json
{
  "aggs": {
    "paginated": {
      "composite": {
        "size": 1000,
        "sources": [
          { "host": { "terms": { "field": "host.name" } } }
        ],
        "after": { "host": "last-host-from-previous-page" }
      }
    }
  }
}
```

### Avoid Script-Based Aggregations in Hot Paths

Scripted aggregations (Painless) are CPU-intensive. For time-critical dashboards:
- Pre-compute expensive metrics with ingest pipelines
- Use dedicated fields instead of runtime calculations
- Reserve scripted aggregations for investigation queries

---

## Index-Level Optimizations

### Refresh Interval

Increase refresh interval for high-throughput ingestion indices:
```json
PUT /wazuh-alerts-000001/_settings
{
  "index.refresh_interval": "30s"  // Reduce from 5s during bulk load
}

// Restore after bulk load:
PUT /wazuh-alerts-000001/_settings
{
  "index.refresh_interval": "5s"
}
```

### Force Merge Before Moving to Warm Tier

Merge segments before promoting to warm tier (ILM handles this automatically via `forcemerge` action):
```bash
POST /wazuh-alerts-000001/_forcemerge?max_num_segments=1
```

### Read-Only Setting on Warm Indices

Warm indices should be read-only to enable OS-level caching:
```json
PUT /wazuh-alerts-000001/_settings
{
  "index.blocks.write": true
}
```

---

## Caching

### Query Cache (Node Level)

Configured in `elasticsearch.yml`:
```yaml
indices.queries.cache.size: 20%
```

Queries in `filter` context are automatically cached. Verify cache usage:
```bash
GET /_nodes/stats/indices/query_cache
```

### Field Data Cache

Used for aggregations on `text` fields (avoid these). For `keyword` fields, fielddata is not needed.

```yaml
indices.fielddata.cache.size: 20%
```

### Shard Request Cache

Aggregation results on entire index are cached at shard level. Enable per-index:
```json
PUT /wazuh-alerts-*/_settings
{
  "index.requests.cache.enable": true
}
```

Check cache hit rate:
```bash
GET /_stats/request_cache
```

---

## Bulk Ingestion Optimization

### Optimal Bulk Request Size

- Target: **5-15 MB** per bulk request
- Too small: high overhead per request
- Too large: memory pressure, GC pauses

```python
# Python example: optimal bulk size
BATCH_SIZE = 500        # documents per request
MAX_BYTES = 10_000_000  # 10 MB max per request
```

### Bulk Thread Pool

In `elasticsearch.yml`:
```yaml
thread_pool.write.size: 8          # 2x CPU cores
thread_pool.write.queue_size: 1000
```

Monitor rejection rate:
```bash
GET /_cat/thread_pool/write?v&h=name,active,rejected,completed
```

---

## Dashboard Query Performance

### Kibana Query Optimization

1. **Use relative time ranges** — `now-1h` is more cacheable than absolute timestamps
2. **Limit panel query complexity** — avoid nested aggregations > 3 levels in dashboards
3. **Set `size: 0`** for all visualization queries (no hits needed)
4. **Use `index.routing.allocation` rules** to co-locate related shards

### Dashboard Refresh Intervals

| Dashboard | Refresh | Rationale |
|---------|---------|----------|
| Security Operations | 30s | Real-time threat monitoring |
| Infrastructure Health | 60s | Metrics update frequency |
| Incident Timeline | Manual | Investigation, not monitoring |
| Threat Intelligence | Manual | Weekly review |
| Executive Summary | Manual | Monthly review |

---

## Benchmarking

Run the included benchmark script to measure query performance:

```bash
cd phase2/elasticsearch/scripts
export ES_HOST=localhost
export ELASTIC_PASSWORD=your_password
bash benchmark-queries.sh
```

Target: **all queries < 5 seconds average**.

### Interpreting Results

```
── Benchmark: brute-force-detection (index: wazuh-alerts-*,logs-auth-*) ──
  Run 1: wall=1205ms  ES.took=342ms
  Run 2: wall=890ms   ES.took=215ms   ← cached
  Run 3: wall=876ms   ES.took=198ms
  ─────────────────────────────
  Min: 876ms | Max: 1205ms | Avg: 990ms
  Status: PASS (< 5s target)
```

- `ES.took` = time spent inside Elasticsearch
- `wall` = total round-trip including network
- Significant drop from Run 1 → Run 2 confirms caching is working

---

## Monitoring Elasticsearch Health

```bash
# Cluster health
GET /_cluster/health?pretty

# Index stats
GET /wazuh-alerts-*/_stats?pretty

# Slow query log (check logs at /var/log/elasticsearch/)
# Already configured in elasticsearch-optimized.yml:
# index.search.slowlog.threshold.query.warn: 10s

# Node stats
GET /_nodes/stats?pretty

# ILM status
GET /wazuh-alerts-*/_ilm/explain?pretty
```
