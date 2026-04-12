# ECS Field Mapping Reference

## Elastic Common Schema (ECS) Compliance

All Phase 2 indices are aligned with [ECS 8.x](https://www.elastic.co/guide/en/ecs/current/index.html). This enables:
- Consistent querying across index patterns
- Cross-index correlations in Kibana
- Compatibility with Elastic Security features
- Phase 3 ML/AI model compatibility

---

## Core Field Groups

### Base Fields

| ECS Field | Type | Description | Example |
|-----------|------|-------------|---------|
| `@timestamp` | date | Event timestamp (UTC, ISO 8601) | `2024-01-15T14:32:01.000Z` |
| `tags` | keyword[] | Custom classification labels | `["brute-force", "soc-alert"]` |
| `labels` | object | Key-value metadata | `{"env": "prod"}` |
| `message` | text | Human-readable summary | `Failed SSH login from 10.0.0.1` |

### Host Fields (`host.*`)

| ECS Field | Type | Description |
|-----------|------|-------------|
| `host.name` | keyword | FQDN or short hostname |
| `host.hostname` | keyword | Hostname only (no domain) |
| `host.ip` | ip[] | Host IP addresses |
| `host.id` | keyword | Unique host identifier |
| `host.os.family` | keyword | OS family (linux, windows, macos) |
| `host.os.name` | keyword | OS name (Ubuntu, Windows Server) |
| `host.os.platform` | keyword | OS platform (ubuntu, windows) |
| `host.os.version` | keyword | OS version (22.04, 2022) |

### User Fields (`user.*`)

| ECS Field | Type | Description |
|-----------|------|-------------|
| `user.name` | keyword | Username (normalized lowercase) |
| `user.id` | keyword | User ID / UID |
| `user.domain` | keyword | Domain name |
| `user.effective.name` | keyword | Effective user (after su/sudo) |

### Event Fields (`event.*`)

| ECS Field | Type | Description | Values |
|-----------|------|-------------|--------|
| `event.action` | keyword | Action observed | `ssh_login`, `sudo`, `file_created` |
| `event.category` | keyword[] | Event category | `authentication`, `network`, `file`, `process` |
| `event.type` | keyword[] | Event type | `start`, `end`, `access`, `change`, `info` |
| `event.outcome` | keyword | Success/failure | `success`, `failure`, `unknown` |
| `event.kind` | keyword | Event kind | `event`, `alert`, `metric`, `state` |
| `event.module` | keyword | Source module | `ssh`, `sudo`, `wazuh`, `zabbix` |
| `event.dataset` | keyword | Specific dataset | `auth`, `syslog`, `alerts` |
| `event.severity` | integer | Numeric severity (1-15) | Wazuh rule level |

### Source/Destination Fields

| ECS Field | Type | Description |
|-----------|------|-------------|
| `source.ip` | ip | Origin IP of request/connection |
| `source.port` | integer | Source port |
| `source.user.name` | keyword | User at source |
| `source.geo.location` | geo_point | Latitude/Longitude |
| `source.geo.country_name` | keyword | Country name |
| `source.geo.country_iso_code` | keyword | ISO 2-letter country code |
| `source.geo.city_name` | keyword | City name |
| `source.geo.region_name` | keyword | Region/state name |
| `destination.ip` | ip | Destination IP |
| `destination.port` | integer | Destination port |

### Network Fields (`network.*`)

| ECS Field | Type | Description |
|-----------|------|-------------|
| `network.bytes` | long | Total bytes transferred |
| `network.direction` | keyword | `inbound`, `outbound`, `internal` |
| `network.protocol` | keyword | Protocol name (`tcp`, `udp`, `http`) |
| `network.transport` | keyword | Transport protocol |

### Process Fields (`process.*`)

| ECS Field | Type | Description |
|-----------|------|-------------|
| `process.name` | keyword | Process name |
| `process.pid` | long | Process ID |
| `process.executable` | keyword | Full path to executable |
| `process.command_line` | wildcard | Full command line |
| `process.parent.name` | keyword | Parent process name |

---

## Wazuh-Specific Field Mapping

Wazuh fields mapped to ECS equivalents:

| Wazuh Field | ECS Field | Notes |
|-------------|----------|-------|
| `agent.name` | `host.name` | Agent hostname |
| `agent.ip` | `host.ip` | Agent IP |
| `rule.level` | `event.severity` | Numeric severity (1-15) |
| `rule.description` | `rule.description` | Alert description |
| `rule.id` | `rule.id` | Rule identifier |
| `data.srcip` | `source.ip` | Attack source IP |
| `data.dstip` | `destination.ip` | Target IP |
| `data.srcuser` | `user.name` | Affected username |
| `timestamp` | `@timestamp` | Event time |
| `location` | `event.module` | Log source |

---

## Metrics-Specific Field Mapping

Zabbix item keys mapped to ECS system fields:

| Zabbix Item Key | ECS Field | Unit |
|----------------|----------|------|
| `system.cpu.util` | `system.cpu.total.pct` | 0.0-1.0 |
| `system.cpu.load[percpu,avg1]` | `system.load.1` | float |
| `system.cpu.load[percpu,avg5]` | `system.load.5` | float |
| `system.cpu.load[percpu,avg15]` | `system.load.15` | float |
| `vm.memory.size[total]` | `system.memory.total` | bytes |
| `vm.memory.size[available]` | `system.memory.free` | bytes |
| `vm.memory.size[pavailable]` | `system.memory.actual.used.pct` | 0.0-1.0 |
| `vfs.fs.size[/,total]` | `system.disk.total` | bytes |
| `vfs.fs.size[/,used]` | `system.disk.used.bytes` | bytes |
| `vfs.fs.size[/,pused]` | `system.disk.used.pct` | 0.0-1.0 |
| `net.if.in[eth0]` | `system.network.in.bytes` | bytes/sec |
| `net.if.out[eth0]` | `system.network.out.bytes` | bytes/sec |

---

## Custom Fields (Phase 2 Additions)

Fields added by Phase 2 not in standard ECS:

| Custom Field | Type | Description |
|-------------|------|-------------|
| `correlation.id` | keyword | Unique correlation event ID |
| `correlation.rule` | keyword | Correlation rule that triggered |
| `correlation.severity` | keyword | SOC severity classification |
| `correlation.chain_id` | keyword | Attack chain identifier |
| `rule.mitre.id` | keyword | MITRE ATT&CK technique ID |
| `rule.mitre.tactic` | keyword | MITRE ATT&CK tactic |
| `rule.mitre.technique` | keyword | MITRE ATT&CK technique name |
| `zabbix.host_id` | keyword | Zabbix internal host ID |
| `zabbix.item_id` | keyword | Zabbix item identifier |
| `zabbix.item_key` | keyword | Zabbix item key string |
| `zabbix.group_name` | keyword | Zabbix host group |

---

## Field-Level Security (RBAC)

Configure Elasticsearch role-based field access:

```json
POST /_security/role/soc-analyst
{
  "indices": [
    {
      "names": ["wazuh-alerts-*", "logs-auth-*"],
      "privileges": ["read"],
      "field_security": {
        "grant": [
          "@timestamp", "host.name", "source.ip", "user.name",
          "event.*", "rule.*", "tags", "correlation.*"
        ],
        "except": ["full_log"]  // Hide raw log line from analysts
      }
    }
  ]
}
```

```json
POST /_security/role/soc-investigator
{
  "indices": [
    {
      "names": ["wazuh-alerts-*", "wazuh-archives-*", "logs-*"],
      "privileges": ["read"],
      "field_security": {
        "grant": ["*"]  // Full field access for investigators
      }
    }
  ]
}
```
