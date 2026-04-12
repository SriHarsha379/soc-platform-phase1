# Scaling Recommendations

## Overview

This guide describes how to scale the Phase 2 SOC platform from a single-node MVP to a production-grade multi-node cluster, and provides capacity planning formulas.

---

## Current MVP (Single Node)

The Phase 2 baseline uses a single Elasticsearch node handling all tiers:

```
┌─────────────────────────────────┐
│     Single ES Node (MVP)        │
│  Role: master + hot + warm +    │
│        cold + ingest            │
│  RAM: 8-16 GB                   │
│  Heap: 4-8 GB (50% of RAM)      │
│  Storage: SSD 500 GB            │
└─────────────────────────────────┘
```

**Capacity:** ~2,000-5,000 events/second

---

## Scale-Out Path

### Phase 2A: 3-Node Cluster (5,000-10,000 events/sec)

Add two additional nodes, enable HA with replica shards:

```
Node 1 (master + hot)  →  Node 2 (hot + ingest)  →  Node 3 (warm + cold)
     ↑                                                      ↑
  Active writes                                      Read-only archives
```

Configuration changes needed:
- Set `discovery.seed_hosts` and `cluster.initial_master_nodes`
- Add node attributes: `-E node.attr.data=hot` or `warm` or `cold`
- Update ILM policies to use `require: { "data": "warm" }` and `require: { "data": "cold" }`

### Phase 2B: 6-Node Cluster (10,000-50,000 events/sec)

Dedicated master nodes + dedicated data nodes:

```
3 dedicated master nodes (no data) +
3 hot data nodes (active writes) +
2 warm data nodes (read-only) +
1 cold data node (archives)
```

### Phase 3 (AI/ML Ready): 10+ Node Cluster

Add dedicated ML nodes for anomaly detection (Phase 3 prerequisite):
- 2 ML nodes with `node.roles: [ml]`
- Expand hot tier to 5+ nodes for 50,000+ events/sec

---

## Capacity Planning Formulas

### Storage Estimation

```
Daily storage = events_per_day × avg_event_size_bytes × (1 + compression_ratio) × replicas

Example:
  Events/day = 10,000,000 (10k/sec × 86,400 sec)
  Avg event size = 1,500 bytes (typical Wazuh alert)
  Compression ratio = 0.5 (best_compression codec)
  Replicas = 1 (doubles raw storage)

  Daily storage = 10,000,000 × 1,500 × (1 + 0.5) × 2
               = 45 GB/day
  Monthly = 45 GB × 30 = 1.35 TB/month
  Annual = 45 GB × 365 = ~16 TB/year
```

Adjust for your event volume and enable ILM to auto-delete after retention period.

### Heap Size Recommendation

```
Heap = min(50% of RAM, 31 GB)

Server RAM   Heap
  8 GB    →  4 GB
  16 GB   →  8 GB
  32 GB   →  16 GB
  64 GB   →  31 GB  (max; compressed OOPs limit)
```

### CPU Core Recommendation

```
Indexing throughput ≈ 2,000 events/sec per CPU core (assuming ECS-normalized)
Query concurrency ≈ 50 concurrent queries per CPU core

For 10,000 events/sec target:
  Indexing cores = 10,000 / 2,000 = 5 cores
  Plus overhead (OS, JVM GC, etc.) × 2 = 10 cores minimum
```

---

## Index Shard Strategy by Scale

| Daily Volume | Shards | Replicas | Node Count |
|-------------|--------|---------|-----------|
| < 5 GB | 1 | 0 (dev) or 1 (prod) | 1+ |
| 5-20 GB | 1 | 1 | 2+ |
| 20-50 GB | 3 | 1 | 3+ |
| 50-150 GB | 5 | 1 | 5+ |
| > 150 GB | 10 | 2 | 10+ |

**Rule:** Target 10-40 GB per shard after merge. Use `forcemerge` on warm indices.

---

## Ingestion Tuning

### Bulk API Settings

```yaml
# Per node in elasticsearch.yml
thread_pool.write.size: <2 × CPU_CORES>     # e.g., 8 for 4-core
thread_pool.write.queue_size: 1000
indices.memory.index_buffer_size: 20%       # 20% of heap for indexing buffer
```

### Bulk Request Sizing

```
Target bulk request: 5-15 MB per request
Optimal: 1,000-5,000 documents per request (adjust for doc size)

For Zabbix metrics (~500 bytes): 10,000 docs per bulk request
For Wazuh alerts (~1,500 bytes): 3,000 docs per bulk request
```

### Translog Durability

For high throughput, use async translog (accepts risk of losing up to `sync_interval` of data on crash):

```yaml
index.translog.durability: async
index.translog.sync_interval: 5s
```

For critical security data (wazuh-alerts), keep `request` durability if data integrity is paramount.

---

## Monitoring & Alerting for ES Health

Set up Kibana alerting rules for:

| Metric | Warning | Critical | Action |
|--------|---------|---------|--------|
| Cluster status | yellow | red | Page on-call |
| Heap usage | 75% | 85% | Investigate memory pressure |
| Disk usage | 75% | 85% | Add storage or delete old indices |
| Write rejection rate | > 0 | > 10/min | Scale write thread pool |
| Search latency (p99) | > 3s | > 10s | Optimize queries, scale search |
| JVM GC time | > 10% | > 25% | Tune heap, investigate memory |

Monitor with:
```bash
# Real-time cluster stats
watch -n5 'curl -s elastic:pass@localhost:9200/_cluster/health?pretty'

# Pending tasks
curl -s elastic:pass@localhost:9200/_cluster/pending_tasks

# Node hot threads (CPU investigation)
curl -s elastic:pass@localhost:9200/_nodes/hot_threads
```

---

## Logstash / Beats Scaling

If using Logstash as ingest pipeline:

```
Agents → Logstash (N instances) → Elasticsearch

Scale Logstash horizontally behind a load balancer:
  1 Logstash instance ≈ 10,000-20,000 events/sec
  For 50,000 events/sec: 3-5 Logstash instances
```

Alternative: Use Elasticsearch Ingest Pipelines directly (no Logstash needed for simple normalization).

---

## Phase 3 Preparation

Phase 3 will add AI/ML capabilities. Prepare by:

1. **Keep raw data accessible** — don't over-compress hot indices
2. **Normalize fields consistently** — ECS compliance is critical for ML feature extraction
3. **Maintain field cardinality** — limit high-cardinality fields in hot indices
4. **Add ML node capacity** early — ML jobs are CPU/memory intensive
5. **Ensure geo-data quality** — Impossible Travel ML models require accurate geolocation
6. **Baseline period** — Collect 30-90 days of normalized data before enabling anomaly detection
