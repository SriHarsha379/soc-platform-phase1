# Correlation Rules Reference

This directory contains the **correlation rule definitions** for the Phase 2 SOC platform analytics layer.

Each JSON file defines a detection rule that drives correlation logic in Elasticsearch and/or Wazuh.

---

## Rule Summary

| Rule File | Severity | Detection Method | MITRE Technique |
|-----------|----------|-----------------|-----------------|
| `brute-force.json` | Medium | Threshold: 5+ failed logins / 5 min / same IP | T1110 |
| `privilege-escalation.json` | High | Sequence: failed auth → sudo success (15 min) | T1548.003 |
| `data-exfiltration.json` | Critical | Aggregation: outbound bytes > 1 GB / 5 min | T1048 |
| `impossible-travel.json` | High | Geo-velocity: travel speed > 900 km/h | T1078.004 |
| `time-anomaly.json` | Medium | Schedule: access outside 09:00-18:00 Mon-Fri | T1078.004 |

---

## Rule Structure

Each rule JSON contains:

```json
{
  "id": "unique-rule-id",
  "name": "Human-readable name",
  "description": "What the rule detects and why",
  "severity": "critical|high|medium|low",
  "mitre": { "tactic": "...", "technique": "T1xxx" },
  "detection": { ... },
  "wazuh_rule_ids": [...],
  "alert_output": { ... },
  "false_positive_guidance": [...],
  "remediation_steps": [...]
}
```

---

## Detection Types

### 1. Threshold Detection (`brute-force.json`)
Counts events matching a query within a time window per-field.
Fires when count exceeds the threshold.

```
IF count(failed_logins WHERE source.ip = X) >= 5 IN LAST 5 minutes
THEN alert(severity=medium, tag=brute-force-detected)
```

**Implementation:** Elasticsearch aggregation + Wazuh frequency rules

### 2. Sequence Detection (`privilege-escalation.json`)
Tracks ordered event sequences correlated by a common field.

```
IF failed_login by user X
THEN within 15 minutes: sudo_success by same user X
THEN alert(severity=high, tag=privilege-escalation-detected)
```

**Implementation:** Wazuh `if_matched_sid` + `timeframe` rules

### 3. Aggregation Threshold (`data-exfiltration.json`)
Aggregates metric values and fires when cumulative sum exceeds threshold.

```
IF sum(bytes_sent WHERE destination NOT IN internal_networks) > 1 GB IN 5 minutes
THEN alert(severity=critical, tag=data-exfiltration-suspected)
```

**Implementation:** Elasticsearch aggregation query (scheduled via Kibana Alerting or cron)

### 4. Geo-Velocity (`impossible-travel.json`)
Calculates travel speed between consecutive login locations for the same user.

```
IF login by user X from location A
THEN within 4 hours: login by same user X from location B
WHERE haversine_distance(A, B) / time_delta > 900 km/h
THEN alert(severity=high, tag=impossible-travel-detected)
```

**Implementation:** Elasticsearch scripted aggregation + Painless distance formula

### 5. Time Window (`time-anomaly.json`)
Fires when an event occurs outside defined business hours.

```
IF successful_login
WHERE hour(timestamp) < 9 OR hour(timestamp) >= 18
OR weekday(timestamp) IN (Saturday, Sunday)
THEN alert(severity=medium, tag=off-hours-access-detected)
```

**Implementation:** Wazuh `<time>` and `<weekday>` rule conditions

---

## Alert Severity Model

| Level | Wazuh Rule Level | Response SLA | Actions |
|-------|-----------------|-------------|---------|
| Critical | 13-15 | Immediate | Page on-call, create P1 ticket, optional auto-response |
| High | 10-12 | Within 1 hour | Email SOC, create ticket, escalate to Tier 2 |
| Medium | 7-9 | Within 4 hours | Email SOC, create ticket |
| Low | 3-6 | Same business day | Log, review in daily standup |

---

## Deduplication Strategy

To reduce alert fatigue:

1. **Same source IP, same rule:** Suppress duplicate alerts within 1 hour window
2. **Same user, privilege escalation:** Group events within 30-minute window
3. **Same host, data exfiltration:** Suppress repeats within 15 minutes
4. **Off-hours access, same user:** Group within 4-hour window

Deduplication is implemented via Wazuh `frequency` rules and Elasticsearch dedup fields.

---

## Extending Rules

To add a new correlation rule:

1. Create a new JSON file in this directory following the schema above
2. If using Wazuh: add corresponding XML rules in `../wazuh/rules/`
3. If using ES aggregation: add the query to `../elasticsearch/queries/`
4. Document the rule in this README
5. Deploy with `../scripts/deploy-wazuh-rules.sh` or `../scripts/phase2-setup.sh`

---

## References

- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [Elastic Common Schema (ECS)](https://www.elastic.co/guide/en/ecs/current/index.html)
- [Wazuh Rule Syntax](https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html)
- [Elasticsearch Query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)
