# SOC Platform Phase 1

> **AI-Powered Security Operations Center - Foundational Implementation**
>
> Real-time infrastructure monitoring, security log collection, centralized dashboards, and automated alerting using 100% open-source tools.

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SOC PLATFORM - PHASE 1                       │
├─────────────────────────────────────────────────────────────────┤
│  Endpoints → Zabbix Agent / Wazuh Agent                          │
│       ↓                    ↓                                     │
│  Zabbix Server        Wazuh Manager                              │
│  (PostgreSQL)              ↓                                     │
│       ↓           Elasticsearch (8.x)                            │
│  Zabbix Web UI         ↓       ↓                                 │
│  (port 8080)     Kibana     SOC Alerting                         │
│                 (port 5601)  Service (Python)                    │
│                                   ↓                              │
│                            Email (SMTP)                          │
└─────────────────────────────────────────────────────────────────┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full architecture diagram.

---

## 🚀 Quick Start

### Prerequisites

- Ubuntu 20.04/22.04 (or any Linux with Docker)
- Docker 24.x + Docker Compose v2
- 8 GB RAM minimum (16 GB recommended)
- 50 GB disk space

### Deploy in 4 Steps

```bash
# 1. Clone
git clone https://github.com/SriHarsha379/soc-platform-phase1.git
cd soc-platform-phase1

# 2. Configure
cp .env.example .env
nano .env   # Set passwords and SMTP credentials

# 3. Deploy
chmod +x scripts/*.sh tests/*.sh
./scripts/init-setup.sh

# 4. Verify
./scripts/health-check.sh
```

---

## 🧩 Stack

| Component | Tool | Version | Purpose |
|-----------|------|---------|---------|
| Infrastructure Monitoring | Zabbix | 6.4 | CPU, Memory, Disk, Network |
| SIEM | Wazuh | 4.7.0 | Security log collection & analysis |
| Data Store | Elasticsearch | 8.11 | Centralized log storage |
| Visualization | Kibana | 8.11 | Security dashboards |
| Database | PostgreSQL | 15 | Zabbix backend |
| Alerting | Python 3.11 | custom | Email alerts via SMTP |

---

## 📊 Dashboards

| Dashboard | URL | Credentials |
|-----------|-----|-------------|
| Kibana | http://localhost:5601 | elastic / `<ELASTIC_PASSWORD>` |
| Zabbix | http://localhost:8080 | Admin / zabbix |

---

## 🔔 Alerting

Email alerts are sent for:

| Trigger | Threshold | Severity |
|---------|-----------|---------|
| High CPU | > 85% for 5 min | High |
| High Memory | > 90% | High |
| Low Disk | > 85% used | Critical |
| Host Down | No response for 5 min | Critical |
| SSH Brute-Force | ≥ 5 failures / 2 min | Critical |
| Failed Sudo | ≥ 3 attempts / 5 min | High |
| Root SSH Login | Any | High |
| Critical File Modified | /etc/passwd, /etc/shadow | Critical |

---

## 📁 Repository Structure

```
soc-platform-phase1/
├── docker-compose.yml              # Main container orchestration
├── .env.example                    # Environment template
├── alerting/
│   ├── alerting_service.py         # Python SMTP alerting service
│   ├── Dockerfile                  # Alerting service container
│   └── requirements.txt
├── config/
│   ├── zabbix/
│   │   ├── zabbix_server.conf      # Zabbix server config
│   │   ├── hosts_templates.json    # Host & template definitions
│   │   └── alert_actions.sql       # Alert action configurations
│   ├── wazuh/
│   │   ├── ossec.conf              # Wazuh manager config
│   │   ├── rules/
│   │   │   ├── local_rules.xml     # Custom security rules (Rules 100001-100040)
│   │   │   └── decoders/local.xml  # Custom log decoders
│   │   └── agent_configs/
│   │       └── agent.conf          # Agent config template
│   ├── elasticsearch/
│   │   ├── elasticsearch.yml       # ES configuration
│   │   └── jvm.options             # JVM settings
│   ├── kibana/
│   │   └── kibana.yml              # Kibana configuration
│   └── alerting/
│       ├── smtp_config.conf        # SMTP settings
│       └── alert_templates.json    # Alert message templates
├── docs/
│   ├── ARCHITECTURE.md             # Architecture overview & diagram
│   ├── SETUP_GUIDE.md              # Step-by-step setup
│   ├── RUNBOOKS.md                 # Operations runbooks
│   └── API_INTEGRATION.md          # API integration details
├── scripts/
│   ├── init-setup.sh               # Initial deployment (run this first)
│   ├── deploy-zabbix.sh            # Zabbix deployment
│   ├── deploy-wazuh.sh             # Wazuh + Elasticsearch deployment
│   ├── configure-alerts.sh         # Alert configuration
│   └── health-check.sh             # System health verification
├── terraform/
│   ├── main.tf                     # AWS EC2 infrastructure
│   ├── variables.tf                # Input variables
│   └── outputs.tf                  # Output values
└── tests/
    ├── test_zabbix_api.sh          # Zabbix API integration tests
    ├── test_wazuh_api.sh           # Wazuh API integration tests
    └── test_alerts.sh              # Alert system tests
```

---

## 🔒 Security Features

- ✅ Authentication on all dashboards (Kibana X-Pack, Zabbix password)
- ✅ Elasticsearch X-Pack security enabled
- ✅ RBAC-ready (Kibana spaces, Elasticsearch roles)
- ✅ File Integrity Monitoring via Wazuh syscheck
- ✅ 90-day log retention with ILM
- ✅ Network isolation via Docker internal network
- ✅ MITRE ATT&CK framework mapped to detection rules
- ✅ TLS/SSL configurable (`TLS_ENABLED=true` in .env)

---

## 🧪 Testing

```bash
# Run all tests
./tests/test_zabbix_api.sh
./tests/test_wazuh_api.sh
./tests/test_alerts.sh
```

---

## ☁️ Cloud Deployment (AWS)

Infrastructure-as-Code with Terraform:

```bash
cd terraform/

# Initialize
terraform init

# Plan
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# Deploy
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

See outputs for public IP and dashboard URLs.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, component details, data flow |
| [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | Step-by-step deployment guide |
| [RUNBOOKS.md](docs/RUNBOOKS.md) | Daily operations and incident response |
| [API_INTEGRATION.md](docs/API_INTEGRATION.md) | REST API reference for all components |

---

## 🗺 Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **Phase 1** | Foundation: Monitoring, SIEM, Dashboards, Alerting | ✅ **Current** |
| **Phase 2** | Analytics: Logstash enrichment, advanced correlation, threat intel | 🔜 Planned |
| **Phase 3** | AI: ML anomaly detection, SOAR integration, predictive analysis | 🔜 Planned |

---

## License

MIT License - See [LICENSE](LICENSE) for details.