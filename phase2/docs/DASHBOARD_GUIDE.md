# Dashboard Usage Guide

## Overview

Phase 2 provides five Kibana dashboards for different SOC use cases. All dashboards are pre-configured with the correct index patterns and common filters.

**Access Kibana:** `http://<kibana-host>:5601`  
**Credentials:** `elastic` / `<ELASTIC_PASSWORD>`

---

## Dashboard 1: SOC Security Operations

**URL:** `Dashboards → SOC Security Operations`  
**Default Time Range:** Last 24 hours  
**Auto-Refresh:** Every 30 seconds  

### Panels

| Panel | Type | Description |
|-------|------|-------------|
| Alert Summary | Metric | Total alerts: last 24h, 1h, 15m |
| Events Over Time | Bar chart | Stacked bars by rule level, 1-hour buckets |
| Severity Breakdown | Donut chart | % by critical / high / medium / low |
| Top Hosts | Horizontal bar | Top 10 hosts by alert count |
| Top Users | Horizontal bar | Top 10 users by alert count |
| Geographic Map | Heatmap | Source IP origins, bubble = event count |
| Alert Table | Discover | Raw alerts with drill-down links |

### How to Use

1. **Set time range:** Click the time picker (top right). Use relative ranges like "Last 1 hour" for active incidents or "Last 7 days" for trend analysis.

2. **Filter by host:** Click on a hostname in the "Top Hosts" chart, or add a KQL filter:
   ```
   host.name: "web-server-01"
   ```

3. **Filter by severity:** Add KQL filter:
   ```
   rule.groups: "soc-critical" OR rule.groups: "soc-high"
   ```

4. **Drill down into an alert:** Click any row in the Alert Table to expand the full JSON document. Use the "Open in Discover" button for raw log search.

5. **Geographic investigation:** Click a bubble on the map to filter to that source country/IP.

---

## Dashboard 2: Infrastructure Health

**URL:** `Dashboards → Infrastructure Health`  
**Default Time Range:** Last 6 hours  
**Auto-Refresh:** Every 60 seconds  

### Panels

| Panel | Type | Description |
|-------|------|-------------|
| CPU Utilization | Gauge | Average CPU % across all hosts |
| Memory Utilization | Gauge | Average memory % across all hosts |
| Disk Utilization | Gauge | Average disk % across all hosts |
| CPU Trends | Line chart | Per-host CPU over time |
| Memory Trends | Line chart | Per-host memory over time |
| Network I/O | Area chart | Inbound vs outbound bytes per host |
| Load Average | Line chart | 1m, 5m, 15m load per host |

### How to Use

1. **Identify resource spikes:** Look for peaks in CPU/Memory trend charts. Click the spike to see the timestamp.

2. **Filter by host:** Add KQL filter to focus on one server:
   ```
   host.name: "db-server-01"
   ```

3. **Compare hosts:** Use the "Split Series" panel option to add a `host.name` breakdown.

4. **Threshold alerts:** Panels show red/amber color coding when values exceed configured thresholds:
   - CPU Warning: 80% | Critical: 95%
   - Memory Warning: 85% | Critical: 95%
   - Disk Warning: 80% | Critical: 90%

---

## Dashboard 3: Incident Timeline Investigation

**URL:** `Dashboards → Incident Timeline Investigation`  
**Default Time Range:** Last 4 hours  
**Auto-Refresh:** Paused (manual investigation)  

### Panels

| Panel | Type | Description |
|-------|------|-------------|
| Event Timeline | Area chart | Events per minute with severity color |
| Severity Progression | Bar chart | How severity changed during incident |
| Affected Hosts | Data table | Hosts with event counts |
| Affected Users | Data table | Users with event counts |
| MITRE Techniques | Tag cloud | ATT&CK techniques observed |
| Chronological Log Table | Discover | Raw events sorted by time |

### Incident Investigation Workflow

```
Step 1: Set the time range to cover the incident window
         Example: 14:00 - 16:00 on the incident date

Step 2: Filter by the affected host or user
         KQL: host.name: "compromised-server-01" OR user.name: "john.doe"

Step 3: Review severity progression
         Did alerts escalate from medium → high → critical?
         If yes: likely sustained attack, not a false positive

Step 4: Use correlation chain ID to group related events
         KQL: correlation.chain_id: "chain-20240101-abc123"
         This shows the full attack chain in one view

Step 5: Drill into raw logs for forensic detail
         Click any row → Expand → View full_log field

Step 6: Export evidence for the incident report
         Click Share → CSV Export on the Discover panel
```

---

## Dashboard 4: Threat Intelligence Analysis

**URL:** `Dashboards → Threat Intelligence Analysis`  
**Default Time Range:** Last 7 days  

### Panels

| Panel | Type | Description |
|-------|------|-------------|
| Threat Origin Map | World map | 7-day attack origins |
| MITRE ATT&CK | Tag cloud | Techniques observed this week |
| Top Attackers | Data table | IPs, geo, event count, severity |
| Attack Timeline | Line chart | Campaign events over 7 days |
| Rule Group Distribution | Pie chart | brute-force vs priv-esc vs etc. |

### Use Cases

1. **Threat hunting:** Look for patterns across 7-day history not visible in real-time view
2. **Attacker profiling:** Track repeat offenders by source IP or country
3. **Campaign detection:** Spot coordinated attacks across multiple hosts/users
4. **MITRE coverage:** Verify detection coverage across ATT&CK tactics

---

## Dashboard 5: Executive Security Summary

**URL:** `Dashboards → Executive Security Summary`  
**Default Time Range:** Last 30 days  

### KPI Panels

| KPI | What to Look For |
|-----|-----------------|
| Total Alerts (30d) | Trend direction (↑ concerning, ↓ improving) |
| Critical Alerts | Should be near 0; escalate immediately if not |
| Alert Reduction % | Higher = better deduplication working |
| Infrastructure Uptime % | Should be > 99.9% |

### Monthly Reporting

Use this dashboard for:
- Weekly SOC manager review
- Monthly security posture report
- Board-level security briefings
- Compliance (SOC 2, ISO 27001) evidence collection

---

## Common KQL Filters Reference

```kql
# Show only high/critical alerts
rule.level: >= 10

# Show alerts from specific host
host.name: "web-server-01"

# Show authentication failures only
event.outcome: "failure" AND event.category: "authentication"

# Show correlation rule alerts only
rule.groups: "soc-correlation"

# Show brute force alerts
rule.groups: "brute-force"

# Show off-hours access
rule.groups: "time-anomaly"

# Show events from specific source IP
source.ip: "192.168.1.100"

# Show specific user activity
user.name: "admin"

# Show geo-risk events
rule.groups: "geo-risk"

# Exclude suppressed/dedup noise
NOT rule.groups: "suppressed"
```

---

## Importing Dashboards

If dashboards are missing from Kibana:
```bash
cd phase2/kibana/scripts
bash import-dashboards.sh
```

Or manually via Kibana UI:
1. Go to `Stack Management → Saved Objects → Import`
2. Upload files from `phase2/kibana/dashboards/*.json`
3. Select "Overwrite existing" if re-importing
