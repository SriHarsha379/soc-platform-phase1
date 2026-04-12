# Index Strategy & Schema Design

## Index Patterns Overview

Phase 2 uses five core index patterns, each with dedicated ILM policies and shard strategies based on expected data volume.

---

## Index Templates

### 1. `wazuh-alerts-*` — Security Alerts

**Purpose:** Primary security event store for Wazuh alerts  
**Write Rate:** High (thousands/min)  
**Retention:** 1 year  

| Setting | Value | Rationale |
|---------|-------|-----------|
| Shards | 3 | Medium-volume: 10-50 GB expected |
| Replicas | 1 | HA + read performance |
| Refresh | 5s | Near-real-time |
| Translog | async 5s | Throughput over durability |
| Codec | best_compression | Storage efficiency for warm/cold |

**Key Fields (ECS):**

```
@timestamp          → Event time (UTC, ISO 8601)
host.name           → Agent hostname
host.ip             → Agent IP address
agent.id            → Wazuh agent ID
agent.name          → Wazuh agent name
source.ip           → Attack source IP
source.geo.location → Geo-coordinates (geo_point)
user.name           → Affected user
event.action        → Action taken (ssh_login, etc.)
event.outcome       → success | failure
event.severity      → Numeric severity
event.category      → authentication | network | etc.
rule.id             → Wazuh rule ID
rule.level          → Wazuh alert level (1-15)
rule.description    → Human-readable description
rule.groups         → Rule category tags
rule.mitre.id       → MITRE technique ID
correlation.id      → Correlation chain identifier
correlation.rule    → Triggered correlation rule name
tags                → Custom labels for filtering
```

---

### 2. `wazuh-archives-*` — Full Log Archives

**Purpose:** Raw log storage for forensic investigation  
**Write Rate:** Very High (all logs, not just alerts)  
**Retention:** 1 year  

| Setting | Value | Rationale |
|---------|-------|-----------|
| Shards | 5 | Large volume (>50 GB expected) |
| Replicas | 1 | HA |
| Refresh | 30s | Archival, not real-time |
| Codec | best_compression | Storage-first design |

**Note:** Archives contain all log events (logall=yes in Wazuh). Use `wazuh-alerts-*` for dashboard queries; archives for forensic searches.

---

### 3. `logs-auth-*` — Authentication Logs

**Purpose:** Dedicated store for authentication events with geo-enrichment  
**Write Rate:** Medium  
**Retention:** 180 days  

| Setting | Value | Rationale |
|---------|-------|-----------|
| Shards | 1 | Small-medium volume |
| Replicas | 1 | HA |
| Refresh | 5s | Near-real-time for correlation |

**Key additional fields:**
- `source.geo.*` — Full geo-location data for impossible travel detection
- `correlation.*` — Correlation chain identifiers

---

### 4. `logs-syslog-*` — System Logs

**Purpose:** Normalized syslog and kernel messages  
**Write Rate:** Medium  
**Retention:** 180 days  

| Setting | Value | Rationale |
|---------|-------|-----------|
| Shards | 1 | Small volume |
| Replicas | 1 | HA |
| Refresh | 10s | Near-real-time |

**Key fields:** `log.syslog.*`, `process.*`, `message`

---

### 5. `metrics-zabbix-*` — Infrastructure Metrics

**Purpose:** Time-series metrics from Zabbix (CPU, memory, disk, network)  
**Write Rate:** High (every 60s per host per metric)  
**Retention:** 90 days  

| Setting | Value | Rationale |
|---------|-------|-----------|
| Shards | 1 | Moderate volume, compresses well |
| Replicas | 1 | HA |
| Refresh | 10s | Dashboard responsiveness |

**Metric Fields:**
```
metric.name          → Zabbix item key (system.cpu.util, etc.)
metric.value         → Raw numeric value
metric.unit          → Unit of measure (%, bytes, etc.)
system.cpu.total.pct → ECS-mapped CPU percentage
system.memory.*      → Memory stats (ECS)
system.disk.*        → Disk stats (ECS)
system.network.*     → Network stats (ECS)
system.load.*        → Load averages (ECS)
zabbix.item_id       → Zabbix item reference
zabbix.host_id       → Zabbix host reference
```

---

## ILM (Index Lifecycle Management) Policies

### Lifecycle Phases

```
┌─────────────────────────────────────────────────────────────────┐
│                    ILM LIFECYCLE FLOW                           │
│                                                                  │
│  DAY 0 ──────── DAY 7 ────────── DAY 30 ─────── DAY 90/180/365│
│                                                                  │
│  [HOT PHASE]  [WARM PHASE]    [COLD PHASE]   [DELETE PHASE]    │
│  Active writes  Read-only       Compressed     Auto-cleanup      │
│  Fast SSD       Warm disk       Cold/object    No manual work    │
│                                 storage                          │
└─────────────────────────────────────────────────────────────────┘
```

| Policy | Hot Rollover | Warm Phase | Cold Phase | Delete |
|--------|-------------|-----------|-----------|--------|
| wazuh-ilm-policy | 20 GB or 7d | 7d | 30d | 365d |
| logs-ilm-policy | 10 GB or 7d | 7d | 30d | 180d |
| metrics-ilm-policy | 5 GB or 7d | 7d | 30d | 90d |

### Rollover Conditions (Hot Phase)
```
Rollover if:
  primary_shard_size >= threshold  (storage-based)
  OR age >= max_age               (time-based)
  OR doc_count >= max_docs        (count-based)
```

---

## Shard Sizing Guidelines

Based on Elastic recommendations:
- **Target shard size:** 10-40 GB per shard
- **Max shards per node:** 1,000 (limit to 500 for headroom)

| Index Size | Shards | Replicas | Notes |
|-----------|--------|---------|-------|
| < 10 GB | 1 | 1 | Typical auth/syslog |
| 10-50 GB | 3 | 1 | Typical alerts |
| > 50 GB | 5 | 1-2 | Archives, high-volume |

---

## Field Normalization

All indices follow the [Elastic Common Schema (ECS) 8.x](https://www.elastic.co/guide/en/ecs/current/index.html) for consistent querying across index patterns.

**Key normalized fields:**

| ECS Field | Type | Description |
|-----------|------|-------------|
| `@timestamp` | date | Event timestamp (always UTC) |
| `host.name` | keyword | Fully qualified hostname |
| `host.ip` | ip | Host IP address |
| `source.ip` | ip | Origin IP of the event |
| `user.name` | keyword | Username (normalized, lowercase) |
| `event.action` | keyword | Action that produced event |
| `event.outcome` | keyword | success / failure / unknown |
| `event.severity` | integer | Numeric severity (1-15) |
| `event.category` | keyword | authentication / network / file |
| `tags` | keyword | Custom classification labels |

---

## Query Optimization Tips

1. **Always filter by `@timestamp` first** — enables shard elimination
2. **Use `keyword` fields for aggregations** — avoid text fields in `terms` aggs
3. **Use `filter` context over `must` where no scoring needed** — query cache friendly
4. **Avoid wildcard queries on large indices** — use `term` or `match` instead
5. **Use index aliases** for seamless rollover and cross-index search
6. **Enable `index.codec: best_compression`** on warm/cold indices — up to 40% storage savings

See [QUERY_OPTIMIZATION.md](QUERY_OPTIMIZATION.md) for detailed tuning guidance.
