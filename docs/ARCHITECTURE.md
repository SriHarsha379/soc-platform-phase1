# SOC Platform Phase 1 - Architecture Overview

## Executive Summary

The SOC Platform Phase 1 delivers a production-ready Security Operations Center foundation using 100% open-source tools. It provides real-time infrastructure monitoring, security event collection, centralized log analysis, interactive dashboards, and automated alerting.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                      SOC PLATFORM - PHASE 1                         │
│                    (Docker Compose / AWS EC2)                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  MONITORED ENDPOINTS                                                 │
│  ┌──────────────────┐    ┌──────────────────┐                       │
│  │  Zabbix Agent    │    │   Wazuh Agent    │                       │
│  │  (port 10050)    │    │  (ports 1514/    │                       │
│  │                  │    │   1515)          │                       │
│  │  Metrics:        │    │  Logs:           │                       │
│  │  - CPU           │    │  - auth.log      │                       │
│  │  - Memory        │    │  - syslog        │                       │
│  │  - Disk          │    │  - audit.log     │                       │
│  │  - Network       │    │  - secure        │                       │
│  └────────┬─────────┘    └────────┬─────────┘                       │
│           │                       │                                  │
│           └───────────┬───────────┘                                  │
│                       │                                              │
│  SOC PLATFORM CORE                                                   │
│  ┌────────────────────┴──────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  ┌─────────────────────┐    ┌───────────────────────────┐    │  │
│  │  │   Zabbix Server     │    │     Wazuh Manager         │    │  │
│  │  │   (port 10051)      │    │     (ports 55000/1514/    │    │  │
│  │  │                     │    │      1515/514)            │    │  │
│  │  │  ┌───────────────┐  │    │                           │    │  │
│  │  │  │  PostgreSQL   │  │    │  Rules: SSH brute-force,  │    │  │
│  │  │  │  (port 5432)  │  │    │  privilege escalation,   │    │  │
│  │  │  └───────────────┘  │    │  file integrity, rootkit  │    │  │
│  │  └──────────┬──────────┘    └──────────────┬────────────┘    │  │
│  │             │                              │                  │  │
│  │             │               ┌──────────────┘                  │  │
│  │             │               │                                  │  │
│  │  ┌──────────▼───────────────▼─────────────────────────────┐  │  │
│  │  │               Elasticsearch (port 9200)                  │  │  │
│  │  │               Single-node cluster (MVP)                  │  │  │
│  │  │                                                          │  │  │
│  │  │  Indices: wazuh-alerts-*, zabbix-metrics-*              │  │  │
│  │  │  ILM: Hot (7d) → Warm (30d) → Delete (90d)             │  │  │
│  │  └──────────────────────────┬───────────────────────────┘   │  │
│  │                             │                                 │  │
│  │  ┌──────────────────────────▼───────────────────────────┐   │  │
│  │  │               Kibana (port 5601)                       │   │  │
│  │  │                                                        │   │  │
│  │  │  Dashboards:                                           │   │  │
│  │  │  - SOC Security Events Overview                        │   │  │
│  │  │  - System Logs Analysis                                │   │  │
│  │  │  - Alert Status Overview                               │   │  │
│  │  └───────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │  ┌────────────────────────────────────────────────────────┐   │  │
│  │  │          Zabbix Web Frontend (port 8080)                │   │  │
│  │  │  - Infrastructure dashboards                            │   │  │
│  │  │  - Trigger/alert management                             │   │  │
│  │  └────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  │  ┌────────────────────────────────────────────────────────┐   │  │
│  │  │          SOC Alerting Service (Python)                  │   │  │
│  │  │  - Polls Elasticsearch every 60s                        │   │  │
│  │  │  - Detects: brute-force, critical events               │   │  │
│  │  │  - Sends email via SMTP                                 │   │  │
│  │  └────────────────────────────────────────────────────────┘   │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                 Email Alert System (SMTP)                       │  │
│  │  Triggers: High CPU, Failed Logins, Host Down, Disk Critical   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Infrastructure Monitoring: Zabbix

| Component | Version | Purpose |
|-----------|---------|---------|
| Zabbix Server | 6.4 (Ubuntu) | Core monitoring engine |
| Zabbix Frontend | 6.4 (Nginx/PgSQL) | Web dashboard |
| Zabbix Agent 2 | 6.4 | Endpoint metric collection |
| PostgreSQL | 15 | Zabbix database backend |

**Monitoring Targets:**
- CPU utilization (5-min average, threshold: 85%)
- Memory availability (threshold: 90% used)
- Disk space usage (threshold: 85%)
- Network I/O (bytes/sec)
- System load average
- Process count
- Host availability (ping check)

### 2. Security Monitoring: Wazuh SIEM

| Component | Version | Purpose |
|-----------|---------|---------|
| Wazuh Manager | 4.7.0 | SIEM engine and rule processor |

**Log Sources:**
- `/var/log/auth.log` – SSH and PAM authentication
- `/var/log/syslog` – System events
- `/var/log/kern.log` – Kernel messages
- `/var/log/audit/audit.log` – Audit daemon events
- Docker container logs (JSON format)

**Custom Rules (IDs 100001-100040):**
- SSH brute-force detection (5+ failures/2min → Level 10)
- Critical brute-force (10+ failures/2min → Level 14)
- Sudo privilege escalation attempts
- Root SSH login detection
- File integrity monitoring (passwd, shadow, sudoers)
- Docker container events
- Firewall rule modifications

### 3. Data Platform: Elasticsearch + Kibana

| Component | Version | Purpose |
|-----------|---------|---------|
| Elasticsearch | 8.11.0 | Log storage and search |
| Kibana | 8.11.0 | Visualization and dashboards |

**Index Management:**
- Pattern: `wazuh-alerts-*`
- ILM Policy: Hot (7d, 10GB rollover) → Warm (30d) → Delete (90d)
- Security: X-Pack enabled, authentication required

### 4. Alerting Service

Custom Python service that:
- Polls Elasticsearch every 60 seconds
- Detects brute-force patterns across aggregated events
- Sends formatted email alerts via SMTP
- Supports configurable thresholds per alert type
- Provides alert templates for different severity levels

---

## Data Flow

```
Endpoint SSH Failure
     │
     ▼
Wazuh Agent ──→ Wazuh Manager ──→ Rule Engine (local_rules.xml)
                                        │
                                   [Rule 100001] Level 5
                                        │
                              [Rule 100002] Level 10 (5+ in 2min)
                                        │
                                   Elasticsearch
                              (wazuh-alerts-YYYY.MM.DD)
                                        │
                                 ┌──────┴──────┐
                                 │             │
                               Kibana      SOC Alerting
                             Dashboard      Service
                                              │
                                         Email Alert
                                     (security-team@...)
```

---

## Security Controls

| Control | Implementation |
|---------|---------------|
| Authentication | Kibana: X-Pack basic auth; Wazuh: JWT API auth; Zabbix: username/password |
| Authorization | Elasticsearch X-Pack RBAC; Kibana spaces |
| Network | Docker internal network; exposed ports limited by Security Group |
| Log Retention | Elasticsearch ILM: 90-day retention policy |
| File Integrity | Wazuh syscheck on /etc, /bin, /usr/bin, /sbin |
| TLS | Configurable (TLS_ENABLED flag); required for production |

---

## Port Reference

| Port | Service | Protocol | Exposed |
|------|---------|----------|---------|
| 8080 | Zabbix Web UI | TCP | Yes |
| 10050 | Zabbix Agent | TCP | Internal |
| 10051 | Zabbix Server | TCP | Yes |
| 9200 | Elasticsearch HTTP | TCP | Yes (restrict in prod) |
| 9300 | Elasticsearch Transport | TCP | Internal |
| 5601 | Kibana | TCP | Yes |
| 55000 | Wazuh Manager API | TCP/HTTPS | Yes |
| 1514 | Wazuh Agent Events | UDP | Yes |
| 1515 | Wazuh Agent Enrollment | TCP | Yes |
| 514 | Syslog | UDP | Yes |
| 5432 | PostgreSQL | TCP | Internal |

---

## Scalability Path

### Phase 2 (Analytics)
- Logstash pipeline for log enrichment
- Multi-node Elasticsearch cluster
- Advanced Kibana SIEM app
- Threat intelligence feeds

### Phase 3 (AI)
- ML-based anomaly detection
- Automated incident response
- Predictive threat analysis
- SOAR platform integration
