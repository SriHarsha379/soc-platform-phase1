# SOC Platform Phase 1 - Setup Guide

## Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 20.04 LTS | Ubuntu 22.04 LTS |
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 50 GB | 100 GB SSD |
| Docker | 24.x | latest |
| Docker Compose | 2.x | latest |

---

## Quick Start (Automated)

```bash
# 1. Clone the repository
git clone https://github.com/SriHarsha379/soc-platform-phase1.git
cd soc-platform-phase1

# 2. Configure environment
cp .env.example .env
nano .env   # Fill in SMTP credentials and passwords

# 3. Run automated setup
chmod +x scripts/*.sh
./scripts/init-setup.sh

# 4. Verify the platform
./scripts/health-check.sh
```

---

## Manual Step-by-Step Setup

### Step 1: Install Docker and Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose v2
sudo apt-get install -y docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

### Step 2: Configure System Requirements

Elasticsearch requires increased virtual memory:

```bash
# Temporary (current session)
sudo sysctl -w vm.max_map_count=262144

# Permanent (survives reboot)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Increase open file limits
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
```

### Step 3: Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and set the following **required** values:

```env
# Change all default passwords
POSTGRES_PASSWORD=<strong-password>
ZABBIX_DB_PASSWORD=<strong-password>
ELASTIC_PASSWORD=<strong-password>
WAZUH_API_PASSWORD=<strong-password>
KIBANA_ENCRYPTION_KEY=<32-char-random-string>

# Configure SMTP for email alerts
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-gmail-app-password  # App password, not account password
SMTP_FROM=soc-alerts@yourdomain.com
ALERT_RECIPIENTS=security-team@yourdomain.com
```

> **Gmail App Password**: Go to Google Account → Security → 2-Step Verification → App passwords

### Step 4: Deploy Zabbix

```bash
./scripts/deploy-zabbix.sh
```

Access Zabbix at: http://localhost:8080  
Default credentials: Admin / zabbix

**Post-deployment tasks in Zabbix UI:**
1. Administration → Users → Admin → Change password
2. Configuration → Host groups → Create "SOC-Monitored-Servers"
3. Configuration → Templates → Import `config/zabbix/hosts_templates.json`
4. Administration → Media types → Configure Email (SMTP)

### Step 5: Deploy Wazuh + Elasticsearch

```bash
./scripts/deploy-wazuh.sh
```

This script:
- Starts Elasticsearch
- Creates the `wazuh-alerts-*` index template
- Sets up 90-day ILM policy
- Starts Wazuh Manager

### Step 6: Start All Services

```bash
docker compose up -d
```

### Step 7: Configure Kibana Dashboards

1. Open Kibana: http://localhost:5601
2. Login with elastic / `<ELASTIC_PASSWORD from .env>`
3. Navigate to: Stack Management → Index Patterns
4. Create pattern: `wazuh-alerts-*` with `@timestamp` as the time field
5. Navigate to: Dashboards → Create dashboard
6. Add visualizations for:
   - Security events by rule level
   - Top attacking IP addresses
   - Authentication failures over time
   - Agent status overview

### Step 8: Configure Alerts

```bash
./scripts/configure-alerts.sh
```

This configures:
- Kibana index patterns
- SOC Security Events dashboard
- Elasticsearch watcher alerts
- Zabbix SMTP media type

### Step 9: Enroll Wazuh Agents

On each endpoint you want to monitor:

```bash
# Download and install agent (Ubuntu/Debian)
curl -so /tmp/wazuh-agent.deb \
    https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb

WAZUH_MANAGER='<your-soc-server-ip>' \
WAZUH_AGENT_NAME='$(hostname)' \
dpkg -i /tmp/wazuh-agent.deb

systemctl enable --now wazuh-agent
```

### Step 10: Verify Deployment

```bash
./scripts/health-check.sh
```

All checks should pass. If not, review:
```bash
docker compose logs <service-name>
docker compose ps
```

---

## Access Details

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Kibana | http://localhost:5601 | elastic / `<ELASTIC_PASSWORD>` |
| Zabbix | http://localhost:8080 | Admin / zabbix |
| Elasticsearch API | http://localhost:9200 | elastic / `<ELASTIC_PASSWORD>` |
| Wazuh API | https://localhost:55000 | wazuh-wui / `<WAZUH_API_PASSWORD>` |

---

## Production Hardening

### 1. Change All Default Passwords

```bash
# Generate strong passwords
openssl rand -base64 32  # Use for each service password

# Update .env file and restart services
docker compose down && docker compose up -d
```

### 2. Enable TLS

```bash
# Generate self-signed certificates (use Let's Encrypt for production)
mkdir -p config/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout config/certs/server.key \
    -out config/certs/server.crt \
    -subj "/CN=soc-platform"

# Enable in .env
TLS_ENABLED=true
```

### 3. Firewall Configuration

```bash
# Allow only required ports
sudo ufw default deny incoming
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 8080/tcp  # Zabbix UI (restrict to admin IPs)
sudo ufw allow 5601/tcp  # Kibana (restrict to admin IPs)
sudo ufw allow 10051/tcp # Zabbix agents
sudo ufw allow 1514/udp  # Wazuh agents
sudo ufw allow 1515/tcp  # Wazuh enrollment
sudo ufw enable
```

### 4. Regular Maintenance

```bash
# Update images monthly
docker compose pull && docker compose up -d

# Backup Elasticsearch data
docker run --rm -v elasticsearch-data:/data -v $(pwd)/backups:/backups \
    alpine tar czf /backups/es-backup-$(date +%Y%m%d).tar.gz /data

# Check disk usage
docker system df
```

---

## Troubleshooting

### Elasticsearch won't start

```bash
# Check vm.max_map_count
sysctl vm.max_map_count
# Should be 262144+

# Fix:
sudo sysctl -w vm.max_map_count=262144
docker compose restart elasticsearch
```

### Wazuh agents not connecting

```bash
# Check Wazuh Manager status
docker compose exec wazuh-manager /var/ossec/bin/wazuh-control status

# Check agent logs on endpoint
tail -f /var/ossec/logs/ossec.log

# Verify firewall ports 1514, 1515 are open
telnet <manager-ip> 1515
```

### Zabbix shows no data

```bash
# Verify agent connectivity
docker compose exec zabbix-server zabbix_get -s zabbix-agent -p 10050 -k agent.ping

# Check server logs
docker compose logs zabbix-server | tail -50
```

### Alert emails not sending

```bash
# Check alerting service logs
docker compose logs soc-alerting

# Verify SMTP settings in .env
# For Gmail: ensure App Password is used, not account password
# Enable 2FA and create App Password at: myaccount.google.com/security
```
