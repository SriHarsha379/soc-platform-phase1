# SOC Platform Phase 1 - Operations Runbooks

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Service Management](#service-management)
3. [Incident Response](#incident-response)
4. [Backup and Recovery](#backup-and-recovery)
5. [Agent Management](#agent-management)
6. [Alert Management](#alert-management)
7. [Log Management](#log-management)

---

## Daily Operations

### Morning Health Check

```bash
cd /path/to/soc-platform-phase1
./scripts/health-check.sh
```

Expected output: All checks PASS

### Check Active Alerts

**Kibana:**
1. Open http://localhost:5601
2. Navigate to Observability → Alerts
3. Filter by last 24 hours

**Zabbix:**
1. Open http://localhost:8080
2. Click Monitoring → Dashboard → Problems

**Command line:**
```bash
# Recent Wazuh alerts (Level 10+)
docker compose exec elasticsearch curl -sf \
    -u elastic:${ELASTIC_PASSWORD} \
    'http://localhost:9200/wazuh-alerts-*/_search' \
    -H 'Content-Type: application/json' \
    -d '{"query":{"bool":{"must":[{"range":{"@timestamp":{"gte":"now-24h"}}},{"range":{"rule.level":{"gte":10}}}]}},"sort":[{"@timestamp":{"order":"desc"}}],"size":10}'
```

---

## Service Management

### Starting All Services

```bash
docker compose up -d
```

### Stopping All Services

```bash
docker compose down
```

### Restarting a Specific Service

```bash
docker compose restart <service-name>
# Examples:
docker compose restart elasticsearch
docker compose restart wazuh-manager
docker compose restart kibana
```

### Viewing Service Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f wazuh-manager
docker compose logs -f elasticsearch
docker compose logs -f kibana
docker compose logs -f soc-alerting

# Last 100 lines
docker compose logs --tail=100 elasticsearch
```

### Checking Service Status

```bash
docker compose ps
```

### Updating Service Images

```bash
# Pull latest images
docker compose pull

# Restart with new images (brief downtime)
docker compose up -d --force-recreate
```

---

## Incident Response

### SSH Brute-Force Attack Response

**Detection:** Wazuh Rule 100002/100003 triggers, email alert received

**Steps:**
1. Identify attacking IP from alert email
2. Block IP immediately:
   ```bash
   # On affected host
   sudo iptables -A INPUT -s <attacker-ip> -j DROP
   sudo iptables-save > /etc/iptables/rules.v4
   ```
3. Verify no successful logins from attacker:
   ```bash
   grep <attacker-ip> /var/log/auth.log | grep "Accepted"
   ```
4. Review Kibana for scope of attack:
   - Navigate to Discover → Filter by `data.srcip: <attacker-ip>`
5. If successful login found:
   - Lock affected account: `sudo passwd -l <username>`
   - Audit all activity: `last <username>`
   - Review bash history: `cat /home/<username>/.bash_history`
   - Rotate SSH keys
6. Document in incident log
7. Consider adding to permanent blocklist

### Host Unreachable Response

**Detection:** Zabbix trigger "Host is unreachable", email alert received

**Steps:**
1. Check if host is a VM or physical server
2. Attempt ping from another host: `ping <host-ip>`
3. Try SSH: `ssh user@<host-ip>`
4. If no response:
   - Check hypervisor/cloud console for VM power state
   - Check network switches/routers for connectivity
   - Review out-of-band console (iDRAC, iLO, IPMI)
5. If VM: attempt hard reset from hypervisor console
6. After recovery: review system logs for cause
   ```bash
   sudo journalctl --since "2 hours ago"
   sudo dmesg | tail -50
   ```

### High CPU Usage Response

**Detection:** Zabbix trigger >85% CPU, email alert received

**Steps:**
1. SSH into affected host
2. Identify processes consuming CPU:
   ```bash
   top -b -n 1 | head -20
   ps aux --sort=-%cpu | head -10
   ```
3. Check for cryptominer signatures:
   ```bash
   # Look for known miner processes
   ps aux | grep -E "xmrig|minerd|cpuminer"
   # Check network connections
   ss -tlnp | grep -v LISTEN
   ```
4. If legitimate: scale resources or optimize application
5. If suspicious: isolate host and escalate to security team
6. Document findings in incident log

### Critical File Modified (FIM Alert)

**Detection:** Wazuh Rule 100030/100031 triggers (/etc/passwd or /etc/shadow modified)

**Steps:**
1. Identify who modified the file:
   ```bash
   sudo ausearch -f /etc/passwd | tail -20
   ```
2. Check for unauthorized user additions:
   ```bash
   cat /etc/passwd | awk -F: '$3 == 0 {print}'  # UID 0 accounts
   diff /etc/passwd /etc/passwd.bak 2>/dev/null || echo "No backup"
   ```
3. If unauthorized change:
   - Disable suspicious account: `sudo passwd -l <username>`
   - Restore from backup if available
   - Investigate how modification was made
   - Check for rootkits: `sudo rkhunter --check`
4. Escalate to CISO if account compromise suspected

---

## Backup and Recovery

### Elasticsearch Backup

```bash
# Create backup directory
mkdir -p /backups/elasticsearch

# Register snapshot repository
curl -X PUT "http://localhost:9200/_snapshot/soc_backup" \
    -u elastic:${ELASTIC_PASSWORD} \
    -H 'Content-Type: application/json' \
    -d '{
      "type": "fs",
      "settings": {
        "location": "/usr/share/elasticsearch/backups"
      }
    }'

# Create snapshot
curl -X PUT "http://localhost:9200/_snapshot/soc_backup/snapshot_$(date +%Y%m%d)" \
    -u elastic:${ELASTIC_PASSWORD} \
    -H 'Content-Type: application/json' \
    -d '{"indices": "wazuh-alerts-*"}'

# Alternatively, volume-level backup
docker run --rm \
    -v elasticsearch-data:/data \
    -v /backups/elasticsearch:/backups \
    alpine tar czf /backups/es-$(date +%Y%m%d).tar.gz /data
```

### Zabbix Database Backup

```bash
# PostgreSQL dump
docker compose exec zabbix-db pg_dump \
    -U zabbix zabbix | gzip > /backups/zabbix-$(date +%Y%m%d).sql.gz
```

### Configuration Backup

```bash
# Backup all configs
tar czf /backups/soc-config-$(date +%Y%m%d).tar.gz \
    config/ .env docker-compose.yml
```

### Restore Elasticsearch

```bash
# Restore from volume backup
docker compose down
docker run --rm \
    -v elasticsearch-data:/data \
    -v /backups/elasticsearch:/backups \
    alpine tar xzf /backups/es-<date>.tar.gz -C /
docker compose up -d
```

---

## Agent Management

### Enroll a New Wazuh Agent

```bash
# On the endpoint (Ubuntu/Debian)
MANAGER_IP="<soc-server-ip>"

curl -so /tmp/wazuh-agent.deb \
    https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb

WAZUH_MANAGER="${MANAGER_IP}" \
WAZUH_AGENT_NAME="$(hostname)" \
dpkg -i /tmp/wazuh-agent.deb

systemctl enable wazuh-agent
systemctl start wazuh-agent

# Verify connection
systemctl status wazuh-agent
```

### List Connected Wazuh Agents

```bash
# Via API
curl -ks \
    -u wazuh-wui:${WAZUH_API_PASSWORD} \
    "https://localhost:55000/agents?status=active"
```

### Remove a Wazuh Agent

```bash
# Get agent ID first
AGENT_ID="<agent-id>"

curl -ks -X DELETE \
    -u wazuh-wui:${WAZUH_API_PASSWORD} \
    "https://localhost:55000/agents/${AGENT_ID}?pretty"
```

### Add a Zabbix Agent Host

1. Open Zabbix Web (http://localhost:8080)
2. Configuration → Hosts → Create host
3. Fill in:
   - Host name: `<hostname>`
   - Groups: `SOC-Monitored-Servers`
   - Agent interface: `<agent-ip>:10050`
4. Templates → Link: `Linux by Zabbix agent`
5. Click Add

---

## Alert Management

### Silence an Alert Temporarily (Zabbix)

1. Monitoring → Problems
2. Click on problem
3. Acknowledge → Add message → Set suppression period

### Tune Alert Thresholds

**Wazuh (rules):**
Edit `config/wazuh/rules/local_rules.xml`

```xml
<!-- Change brute-force threshold from 5 to 10 attempts -->
<rule id="100002" level="10" frequency="10" timeframe="120">
```

Restart Wazuh Manager:
```bash
docker compose restart wazuh-manager
```

**Alerting Service:**
Update `.env`:
```env
FAILED_LOGIN_THRESHOLD=10
CPU_ALERT_THRESHOLD=90
```

Restart alerting service:
```bash
docker compose restart soc-alerting
```

---

## Log Management

### Check Index Sizes

```bash
curl -s "http://localhost:9200/_cat/indices/wazuh-alerts-*?v&s=index" \
    -u elastic:${ELASTIC_PASSWORD}
```

### Manually Delete Old Indices

```bash
# Delete indices older than 90 days (ILM handles this automatically)
curl -X DELETE "http://localhost:9200/wazuh-alerts-2024.01.*" \
    -u elastic:${ELASTIC_PASSWORD}
```

### Update ILM Policy

```bash
curl -X PUT "http://localhost:9200/_ilm/policy/wazuh-alerts-policy" \
    -u elastic:${ELASTIC_PASSWORD} \
    -H 'Content-Type: application/json' \
    -d '{
      "policy": {
        "phases": {
          "delete": {
            "min_age": "60d",
            "actions": {"delete": {}}
          }
        }
      }
    }'
```
