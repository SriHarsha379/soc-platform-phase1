# SOC Platform Phase 1 - API Integration Guide

## Overview

This guide covers the REST APIs for all SOC platform components and how they integrate.

---

## Elasticsearch API

### Base URL
```
http://localhost:9200
```

### Authentication
```bash
# Basic auth header
curl -u elastic:<password> http://localhost:9200/
```

### Common Operations

#### Cluster Health
```bash
curl -u elastic:<password> http://localhost:9200/_cluster/health?pretty
```

#### Search Wazuh Alerts
```bash
# Recent high-severity alerts (level >= 10)
curl -u elastic:<password> \
    -H "Content-Type: application/json" \
    "http://localhost:9200/wazuh-alerts-*/_search?pretty" \
    -d '{
      "query": {
        "bool": {
          "must": [
            {"range": {"@timestamp": {"gte": "now-1h"}}},
            {"range": {"rule.level": {"gte": 10}}}
          ]
        }
      },
      "sort": [{"@timestamp": {"order": "desc"}}],
      "size": 20
    }'
```

#### Aggregate Alerts by Source IP (Brute-Force Detection)
```bash
curl -u elastic:<password> \
    -H "Content-Type: application/json" \
    "http://localhost:9200/wazuh-alerts-*/_search?pretty" \
    -d '{
      "query": {
        "bool": {
          "must": [
            {"range": {"@timestamp": {"gte": "now-5m"}}},
            {"terms": {"rule.groups": ["brute_force"]}}
          ]
        }
      },
      "aggs": {
        "by_source_ip": {
          "terms": {"field": "data.srcip", "size": 10}
        }
      },
      "size": 0
    }'
```

#### Index a Custom Event
```bash
curl -X POST \
    -u elastic:<password> \
    -H "Content-Type: application/json" \
    "http://localhost:9200/wazuh-alerts-$(date +%Y.%m.%d)/_doc" \
    -d '{
      "@timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "rule": {"level": 5, "description": "Custom SOC event"},
      "agent": {"name": "custom-agent"},
      "data": {"message": "Test event"}
    }'
```

---

## Wazuh Manager API

### Base URL
```
https://localhost:55000
```

### Authentication (JWT)
```bash
# Get token
TOKEN=$(curl -ks -X POST \
    -u wazuh-wui:<password> \
    "https://localhost:55000/security/user/authenticate" \
    | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

# Use token in requests
curl -ks -H "Authorization: Bearer $TOKEN" "https://localhost:55000/manager/info"
```

### Common Operations

#### Get Manager Status
```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/manager/status?pretty"
```

#### List All Agents
```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/agents?status=active&pretty"
```

#### Get Agent Details
```bash
AGENT_ID="001"
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/agents/${AGENT_ID}?pretty"
```

#### List Recent Alerts
```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/alerts?pretty&limit=10&sort=-timestamp"
```

#### List Active Rules
```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/rules?status=enabled&pretty"
```

#### Restart Manager
```bash
curl -ks -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/manager/restart?pretty"
```

#### Get Agent Summary
```bash
curl -ks -H "Authorization: Bearer $TOKEN" \
    "https://localhost:55000/overview/agents?pretty"
```

---

## Zabbix API

### Base URL
```
http://localhost:8080/api_jsonrpc.php
```

### Authentication
```bash
# Get auth token
AUTH_TOKEN=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
    | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
```

### Common Operations

#### Get API Version
```bash
curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":1}'
```

#### List Hosts
```bash
curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"host.get\",\"params\":{\"output\":\"extend\"},\"auth\":\"${AUTH_TOKEN}\",\"id\":2}"
```

#### Get Active Triggers (Problems)
```bash
curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d "{
      \"jsonrpc\":\"2.0\",
      \"method\":\"trigger.get\",
      \"params\":{
        \"output\":\"extend\",
        \"filter\":{\"value\":1},
        \"sortfield\":\"priority\",
        \"sortorder\":\"DESC\"
      },
      \"auth\":\"${AUTH_TOKEN}\",
      \"id\":3
    }"
```

#### Create Host Group
```bash
curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d "{
      \"jsonrpc\":\"2.0\",
      \"method\":\"hostgroup.create\",
      \"params\":{\"name\":\"My-Server-Group\"},
      \"auth\":\"${AUTH_TOKEN}\",
      \"id\":4
    }"
```

#### Create Host
```bash
GROUP_ID="<group-id>"
TEMPLATE_ID="<template-id>"  # Get from template.get API call

curl -sf -X POST \
    -H "Content-Type: application/json" \
    "http://localhost:8080/api_jsonrpc.php" \
    -d "{
      \"jsonrpc\":\"2.0\",
      \"method\":\"host.create\",
      \"params\":{
        \"host\":\"new-server\",
        \"interfaces\":[{
          \"type\":1,\"main\":1,\"useip\":1,
          \"ip\":\"192.168.1.100\",\"dns\":\"\",\"port\":\"10050\"
        }],
        \"groups\":[{\"groupid\":\"${GROUP_ID}\"}],
        \"templates\":[{\"templateid\":\"${TEMPLATE_ID}\"}]
      },
      \"auth\":\"${AUTH_TOKEN}\",
      \"id\":5
    }"
```

---

## Kibana API

### Base URL
```
http://localhost:5601
```

### Authentication
```bash
# Basic auth via header
curl -u elastic:<password> -H "kbn-xsrf: true" http://localhost:5601/api/status
```

### Common Operations

#### Check Kibana Status
```bash
curl -u elastic:<password> "http://localhost:5601/api/status?pretty"
```

#### Create Index Pattern
```bash
curl -X POST \
    -u elastic:<password> \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    "http://localhost:5601/api/saved_objects/index-pattern" \
    -d '{
      "attributes": {
        "title": "wazuh-alerts-*",
        "timeFieldName": "@timestamp"
      }
    }'
```

#### List Dashboards
```bash
curl -u elastic:<password> \
    -H "kbn-xsrf: true" \
    "http://localhost:5601/api/saved_objects/_find?type=dashboard&per_page=20"
```

#### Export Dashboard
```bash
DASHBOARD_ID="<dashboard-id>"
curl -u elastic:<password> \
    "http://localhost:5601/api/kibana/dashboards/export?dashboard=${DASHBOARD_ID}" \
    > dashboard_export.json
```

---

## Integration Flows

### Wazuh → Elasticsearch

Wazuh Manager sends alerts directly to Elasticsearch via Filebeat (built into the Wazuh image). Configuration in `config/wazuh/ossec.conf`:

```xml
<indexer>
  <enabled>yes</enabled>
  <hosts>
    <host>https://elasticsearch:9200</host>
  </hosts>
</indexer>
```

### Custom Webhook Integration

To send alerts to external systems (Slack, PagerDuty, etc.):

```python
import requests

def send_to_webhook(alert_data: dict, webhook_url: str) -> None:
    payload = {
        "text": f"SOC Alert: {alert_data['rule']['description']}",
        "attachments": [{
            "color": "danger" if alert_data['rule']['level'] >= 10 else "warning",
            "fields": [
                {"title": "Host", "value": alert_data['agent']['name'], "short": True},
                {"title": "Level", "value": str(alert_data['rule']['level']), "short": True},
                {"title": "Rule ID", "value": alert_data['rule']['id'], "short": True},
            ]
        }]
    }
    requests.post(webhook_url, json=payload, timeout=10)
```

Add `WEBHOOK_URL` to `.env` and import this function in `alerting/alerting_service.py`.

---

## Rate Limits and Best Practices

| API | Recommended Poll Interval | Notes |
|-----|--------------------------|-------|
| Elasticsearch | 60s | Use aggregations, not per-document polling |
| Wazuh API | 30s for status, 5min for full agent list | JWT token expires in 900s |
| Zabbix API | 60s | Cache auth token; reuse within session |
| Kibana API | N/A | Used for setup/configuration, not polling |
