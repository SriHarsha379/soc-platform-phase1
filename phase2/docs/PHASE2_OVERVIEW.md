# Phase 2: Data Analytics & Log Correlation Layer

## Overview

Phase 2 extends the foundational SOC Platform (Phase 1) with a comprehensive **data analytics and log correlation layer**. This enables fast querying, intelligent threat correlation, and actionable security insights from both logs and infrastructure metrics.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SOC PLATFORM - PHASE 2                               │
│              Data Analytics & Log Correlation Layer                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DATA SOURCES                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │  Wazuh SIEM  │    │   Zabbix     │    │   System Logs            │   │
│  │  - Alerts    │    │  Monitoring  │    │   - auth.log             │   │
│  │  - Archives  │    │  - CPU/Mem   │    │   - syslog               │   │
│  │  - FIM       │    │  - Disk/Net  │    │   - audit.log            │   │
│  └──────┬───────┘    └──────┬───────┘    └────────────┬─────────────┘   │
│         │                  │                           │                 │
│         ▼                  ▼                           ▼                 │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                 INGESTION & NORMALIZATION                        │    │
│  │  ┌──────────────┐    ┌──────────────────┐   ┌────────────────┐ │    │
│  │  │ Wazuh Rules  │    │ Zabbix→ES Python │   │  Logstash /    │ │    │
│  │  │ + Decoders   │    │    Exporter      │   │  Filebeat      │ │    │
│  │  │ (Phase 2)    │    │   (config.yaml)  │   │  (optional)    │ │    │
│  │  └──────┬───────┘    └────────┬─────────┘   └───────┬────────┘ │    │
│  │         │                     │                      │          │    │
│  └─────────┴─────────────────────┴──────────────────────┴──────────┘    │
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │               ELASTICSEARCH (Optimized - Phase 2)               │    │
│  │                                                                  │    │
│  │  Hot Tier          Warm Tier           Cold Tier                │    │
│  │  (0-7 days)       (7-30 days)         (30-90 days)             │    │
│  │  Active writes    Read-only            Compressed               │    │
│  │                                                                  │    │
│  │  Index Patterns:                                                 │    │
│  │  wazuh-alerts-*   wazuh-archives-*   logs-auth-*               │    │
│  │  logs-syslog-*    metrics-zabbix-*                              │    │
│  │                                                                  │    │
│  │  ILM Policies: Auto-rollover at 20GB / 7 days                  │    │
│  └──────────────────────────┬──────────────────────────────────────┘    │
│                             │                                            │
│              ┌──────────────┴──────────────┐                            │
│              ▼                             ▼                            │
│  ┌─────────────────────┐    ┌─────────────────────────────────────┐    │
│  │ CORRELATION ENGINE  │    │         KIBANA DASHBOARDS           │    │
│  │                     │    │                                      │    │
│  │ - Brute Force       │    │ - Security Operations               │    │
│  │ - Priv. Escalation  │    │ - Infrastructure Health             │    │
│  │ - Data Exfiltration │    │ - Incident Timeline                 │    │
│  │ - Impossible Travel │    │ - Threat Intelligence               │    │
│  │ - Time Anomalies    │    │ - Executive Summary                 │    │
│  │                     │    │                                      │    │
│  │ Severity Tagging:   │    │ Filters: Time, Host, Severity,      │    │
│  │ critical/high/      │    │ Event Type, User                    │    │
│  │ medium/low          │    │                                      │    │
│  └─────────────────────┘    └─────────────────────────────────────┘    │
│                                                                          │
│  ALERT ENRICHMENT & DEDUPLICATION                                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  + User/Host context  + Historical frequency  + Related events  │    │
│  │  + Alert grouping     + Noise reduction       + Playbook links  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Capabilities Added in Phase 2

### 1. Elasticsearch Optimization
- **ILM Policies:** Auto-rollover at 20 GB or 7 days; 90-day retention
- **Hot-Warm Architecture:** Active writes on hot nodes, compressed storage on warm/cold
- **JVM Tuning:** G1GC, 50% RAM heap, pre-touched memory
- **Thread Pool Tuning:** 8 threads for write/search, 1000 queue depth
- **Query/Field-Data Cache:** 20% heap allocation each

### 2. ECS-Compliant Index Templates
Five structured index templates with normalized fields:

| Template | Pattern | Shards | ILM Policy |
|----------|---------|--------|-----------|
| wazuh-alerts | wazuh-alerts-* | 3 | wazuh-ilm-policy |
| wazuh-archives | wazuh-archives-* | 5 | wazuh-ilm-policy |
| logs-syslog | logs-syslog-* | 1 | logs-ilm-policy |
| logs-auth | logs-auth-* | 1 | logs-ilm-policy |
| metrics-zabbix | metrics-zabbix-* | 1 | metrics-ilm-policy |

### 3. Log Correlation Engine
Five correlation rules detecting real attack patterns:
- **Brute Force:** 5+ failures / 5 min / same IP → Medium alert
- **Privilege Escalation:** Failed auth → sudo success within 15 min → High alert
- **Data Exfiltration:** >1 GB outbound to external IP in 5 min → Critical alert
- **Impossible Travel:** Login speed >900 km/h → High alert
- **Time Anomaly:** Login outside 09:00-18:00 Mon-Fri → Medium alert

### 4. Zabbix → Elasticsearch Metrics
Python exporter (`zabbix_to_es_exporter.py`) polls Zabbix API every 60 seconds and bulk-indexes metrics into `metrics-zabbix-*` indices.

### 5. Advanced Kibana Dashboards
Five purpose-built dashboards with interactive filters, drill-down, and real-time refresh.

### 6. Alert Enrichment & Deduplication
Wazuh enrichment rules add host/user/geo context and suppress repeated low-value alerts to reduce noise by 40%+.

---

## Performance Targets

| Metric | Target | Implementation |
|--------|--------|----------------|
| Ingestion rate | 10,000 events/sec | Async translog, bulk API |
| Query response | < 5 seconds | Shard strategy, query cache |
| Alert noise reduction | > 40% | Dedup rules, grouping |
| Correlation detection | > 80% of patterns | 5 rule types |
| Index retention | 1 year | ILM policies |

---

## Getting Started

See [../scripts/phase2-setup.sh](../scripts/phase2-setup.sh) for the complete automated setup.

Quick start:
```bash
cd phase2/scripts
bash phase2-setup.sh
```

---

## File Structure

```
phase2/
├── elasticsearch/          # ES optimization configs, templates, queries
├── wazuh/                  # Extended rules and decoders
├── metrics-integration/    # Zabbix exporter
├── kibana/                 # Dashboards, searches, visualizations
├── correlation-rules/      # Rule definitions and documentation
├── docs/                   # Technical documentation
└── scripts/                # Orchestration and utility scripts
```
