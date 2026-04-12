# Correlation Logic - Detailed Explanation

## Overview

The correlation engine detects complex attack patterns by linking related events across time, host, user, and network dimensions. Rules are implemented in two complementary layers:

1. **Wazuh Rule Engine** — Real-time correlation on individual log lines
2. **Elasticsearch Aggregations** — Time-window analysis across large event volumes

---

## Rule 1: Brute Force Detection

### Pattern
```
5+ failed SSH/auth events FROM same source IP WITHIN 5 minutes
→ ALERT: Brute Force Attack (severity: medium)
```

### Wazuh Implementation
```xml
<rule id="100001" level="10" frequency="5" timeframe="300">
  <if_matched_sid>5710</if_matched_sid>   <!-- SSH failed login base rule -->
  <same_source_ip />                       <!-- Correlate by source IP -->
  <description>Brute Force: 5+ failed SSH logins from same IP in 5 min</description>
</rule>
```

Key attributes:
- `frequency="5"` — fire after 5 matches
- `timeframe="300"` — within 300 seconds (5 minutes)
- `same_source_ip` — all matches must share same source IP

### Severity Escalation
| Threshold | Timeframe | Level | Severity |
|-----------|---------|-------|---------|
| 5 failures | 5 min | 10 | Medium |
| 10 failures | 2 min | 12 | High |
| 20 failures | 1 min | 14 | Critical (automated) |

### Elasticsearch Query
See `elasticsearch/queries/brute-force-detection.json` — aggregates by `source.ip` field over 5-minute window, filters for `min_doc_count: 5`.

---

## Rule 2: Privilege Escalation

### Pattern
```
PHASE 1: Failed authentication event (any type) by user X on host H
          WITHIN 15 minutes:
PHASE 2: Successful sudo/su command by same user X on same host H
→ ALERT: Privilege Escalation (severity: high)
```

### Wazuh Implementation
```xml
<!-- Phase 1: Detect failed auth -->
<rule id="5710" level="5">...</rule>  <!-- base rule from Wazuh ruleset -->

<!-- Phase 2: Correlate sudo success after failure -->
<rule id="100101" level="13" timeframe="60">
  <if_matched_sid>5710</if_matched_sid>   <!-- Phase 1 was failed SSH login -->
  <if_sid>100100</if_sid>                 <!-- Current event is sudo success -->
  <same_user />                            <!-- Same username -->
  <description>Privilege Escalation: Sudo after failed SSH (1 min window)</description>
</rule>
```

### Why This Matters
This pattern is the hallmark of **credential-based privilege escalation**:
1. Attacker tries to brute-force SSH (fails multiple times)
2. Finds a valid username + password via other means
3. Uses `sudo` to gain root access

The 15-minute window captures delayed escalation attempts.

---

## Rule 3: Data Exfiltration

### Pattern
```
sum(outbound_bytes) FROM host H TO external_destination > 1 GB WITHIN 5 minutes
  WHERE destination NOT IN internal_network_ranges
→ ALERT: Data Exfiltration Suspected (severity: critical)
```

### Detection Logic
1. Filter events with `data.bytes_sent` field
2. Exclude internal destinations (10.x, 172.16.x, 192.168.x)
3. Aggregate total bytes by `host.name` in 5-minute buckets
4. Fire when aggregated total exceeds 1,073,741,824 bytes (1 GB)

### Elasticsearch Aggregation
```json
{
  "aggs": {
    "by_source_host": {
      "terms": { "field": "host.name" },
      "aggs": {
        "total_bytes_sent": { "sum": { "field": "data.bytes_sent" } },
        "suspicious_destinations": {
          "bucket_selector": {
            "buckets_path": { "totalBytes": "total_bytes_sent" },
            "script": "params.totalBytes > 1073741824"
          }
        }
      }
    }
  }
}
```

### Baseline Approach
For mature deployments, compare against 30-day rolling average:
- Alert when current traffic > 3× baseline, regardless of absolute threshold
- Catches low-and-slow exfiltration that stays below 1 GB threshold

---

## Rule 4: Impossible Travel

### Pattern
```
Login by user X from location A at time T1
Login by user X from location B at time T2
WHERE haversine_distance(A, B) / (T2 - T1) > 900 km/h
AND distance(A, B) > 100 km
→ ALERT: Impossible Travel Detected (severity: high)
```

### Haversine Distance Formula (Painless Script)
```javascript
double haversine(double lat1, double lon1, double lat2, double lon2) {
  double R = 6371.0;  // Earth radius in km
  double dLat = Math.toRadians(lat2 - lat1);
  double dLon = Math.toRadians(lon2 - lon1);
  double a = Math.sin(dLat/2) * Math.sin(dLat/2) +
             Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
             Math.sin(dLon/2) * Math.sin(dLon/2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

double distance = haversine(lat1, lon1, lat2, lon2);
double time_hours = (t2_epoch - t1_epoch) / 3600000.0;
double speed = distance / time_hours;
return speed > 900;  // Commercial aircraft max ~900 km/h
```

### GeoIP Enrichment Required
For this rule to work, events must have `source.geo.location` populated.
Enable GeoIP enrichment in Logstash or Wazuh agent configuration.

---

## Rule 5: Time-Based Anomalies

### Pattern
```
Successful login event
WHERE hour(timestamp) < 9 OR hour(timestamp) >= 18
OR weekday(timestamp) IN [Saturday, Sunday]
→ ALERT: Off-Hours Access (severity: medium)
```

### Wazuh Implementation
```xml
<rule id="100300" level="7">
  <if_sid>5715,5718</if_sid>        <!-- SSH/auth success rules -->
  <time>18:00-09:00</time>          <!-- 18:00 to 09:00 = off hours -->
  <description>Off-Hours Access: login outside business hours</description>
</rule>

<rule id="100301" level="8">
  <if_sid>5715,5718</if_sid>
  <weekday>saturday,sunday</weekday>
  <description>Weekend Access: login on weekend</description>
</rule>
```

### Severity Modifiers
- First-time user accessing off-hours: +2 levels
- Login from geo-risk country + off-hours: escalate to high
- Off-hours login followed by privilege escalation: escalate to critical

---

## Composite / Chained Alert Example

### Attack Chain: Brute Force → Login → Privilege Escalation

```
Event 1: 100x SSH failed from 203.0.113.5 to web-server-01 (rule 100001: brute-force)
Event 2: SSH login SUCCESS from 203.0.113.5 as devuser (rule 100400: compromise)
Event 3: sudo COMMAND=bash as devuser on web-server-01 (rule 100401: escalation)
→ COMPOSITE ALERT: Attack Chain Detected (severity: critical)
   Chain ID: chain-20240101-abc123
   Playbook: docs/playbooks/attack-chain-response.md
```

Chained alerts share a `correlation.chain_id` field, enabling:
- Single grouped alert in the SOC dashboard
- Chronological timeline view in Kibana
- One-click investigation from alert to full event chain

---

## Alert Enrichment Pipeline

Each alert is enriched with context before reaching the analyst:

```
Raw Alert
  → Add host profile (known high-value? DMZ? baseline metrics?)
  → Add user profile (admin? service account? first-time?)
  → Add historical frequency (how often does this rule fire?)
  → Add geo-context (login from unusual country?)
  → Add related events (other events in 5-min window same host)
  → Add severity classification (soc-critical/high/medium/low tag)
  → Deduplication check (suppress if same alert within dedup window)
  → ENRICHED ALERT → Kibana / Email / Ticketing System
```

---

## Deduplication Strategy

| Scenario | Dedup Key | Window | Action |
|---------|----------|--------|--------|
| Brute force from same IP | source.ip | 1 hour | Suppress duplicates, increment counter |
| Privilege escalation, same user | user.name | 30 min | Group into single alert |
| Data exfiltration, same host | host.name | 15 min | Suppress, update bytes total |
| Off-hours, same user | user.name | 4 hours | Group into one alert |

Deduplication reduces alert volume by 40%+ without losing signal.
