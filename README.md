# SOC Platform Phase 1

> **AI-Powered Security Operations Center – Phase 1**
>
> A full-stack Security Operations Center platform featuring real-time alert management, AI-driven anomaly detection, automated SOAR playbooks, log search, and multi-tenant access control — all containerised and ready to run with a single command.

---

## Table of Contents

1. [Architecture Overview](#-architecture-overview)
2. [Tech Stack](#-tech-stack)
3. [Prerequisites](#-prerequisites)
4. [Production Setup (Docker Compose — Recommended)](#-production-setup-docker-compose--recommended)
5. [Local Development Setup](#-local-development-setup)
6. [Default Demo Credentials](#-default-demo-credentials)
7. [Application Walkthrough](#-application-walkthrough)
8. [API Reference](#-api-reference)
9. [Data Flow Explained](#-data-flow-explained)
10. [🎬 Recommended Demo Script](#-recommended-demo-script)
11. [Pre-Demo Checklist](#-pre-demo-checklist)
12. [Troubleshooting](#-troubleshooting)
13. [Legacy Infrastructure Stack (Zabbix / Wazuh)](#-legacy-infrastructure-stack-zabbix--wazuh)
14. [Cloud Deployment (AWS)](#️-cloud-deployment-aws)
15. [Repository Structure](#-repository-structure)
16. [Roadmap](#-roadmap)

---

## 🏗 Architecture Overview

```
                         ┌──────────────────────────────────────────┐
                         │           Browser / Client               │
                         └──────────────────┬───────────────────────┘
                                            │ HTTP :80
                         ┌──────────────────▼───────────────────────┐
                         │          Nginx Reverse Proxy             │
                         │  /          → Frontend (React)           │
                         │  /api/      → Backend (Express)          │
                         │  /ai/       → AI Service (FastAPI)       │
                         │  /soar/     → SOAR Service (FastAPI)     │
                         └──┬──────────┬────────────┬───────────────┘
                            │          │            │
           ┌────────────────▼──┐  ┌────▼────┐  ┌───▼──────────┐
           │  Backend          │  │  soc-ai │  │  soc-soar    │
           │  Node.js/Express  │  │ FastAPI │  │  FastAPI     │
           │  Prisma ORM       │  │ Z-score │  │  Playbooks   │
           │  JWT Auth         │  │ scoring │  │  Engine      │
           └──────┬────────────┘  └─────────┘  └──────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   ┌────▼──────┐    ┌────────▼──────┐
   │ PostgreSQL│    │Elasticsearch  │
   │  (app DB) │    │ (log storage) │
   └───────────┘    └───────────────┘
```

### Service Responsibilities

| Service | Technology | Port (internal) | Role |
|---------|-----------|-----------------|------|
| **nginx** | Nginx 1.27 | 80 (public) | Reverse proxy — single entry point |
| **frontend** | React 18 + Vite + Tailwind | 80 (internal) | Dashboard SPA |
| **backend** | Node.js + Express + Prisma | 4000 | REST API, JWT auth, correlation engine |
| **soc-ai** | Python FastAPI | 8000 | Anomaly detection (Z-score) |
| **soc-soar** | Python FastAPI | 8001 | SOAR playbook engine + audit log |
| **postgres** | PostgreSQL 16 | 5432 | Application data (users, alerts, incidents) |
| **elasticsearch** | Elasticsearch 8.11 | 9200 | Security log storage and search |

---

## 🧩 Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Frontend | React 18, Vite, Tailwind CSS | Responsive SOC dashboard UI |
| Backend | Node.js 20, Express, Prisma ORM | REST API + DB layer |
| Auth | JWT (8-hour tokens) + bcryptjs | Stateless multi-tenant auth |
| AI Service | Python 3.11, FastAPI, Pydantic | Statistical anomaly detection |
| SOAR Service | Python 3.11, FastAPI, SQLite | Automated playbook execution |
| Database | PostgreSQL 16 | Persistent application data |
| Log Store | Elasticsearch 8.11 (X-Pack security) | Log ingestion and search |
| Gateway | Nginx 1.27 | Routing, SSL termination point |
| IaC | Terraform | AWS EC2 provisioning |

---

## ✅ Prerequisites

| Requirement | Version | Check |
|-------------|---------|-------|
| Docker | 24.x+ | `docker --version` |
| Docker Compose | v2 (plugin) | `docker compose version` |
| RAM | 4 GB minimum, 8 GB recommended | `free -h` |
| Disk | 10 GB free | `df -h` |

> **Windows/macOS:** Docker Desktop (v4.x+) includes both Docker and Compose v2.

---

## 🚀 Production Setup (Docker Compose — Recommended)

This is the fastest and most reliable way to run the full platform.

### Step 1 — Clone the repository

```bash
git clone https://github.com/SriHarsha379/soc-platform-phase1.git
cd soc-platform-phase1
```

### Step 2 — Create the environment file

```bash
cp .env.example .env
```

The defaults work out-of-the-box for a local demo. For a real deployment, edit `.env` and change at minimum:

```dotenv
SOC_DB_PASSWORD=<strong-password>
JWT_SECRET=<min-32-char-random-string>
ELASTIC_PASSWORD=<strong-password>
```

### Step 3 — Build and start all services

```bash
docker compose -f docker-compose.app.yml up -d --build
```

This command builds images and starts all seven services. First build takes 3–5 minutes.

### Step 4 — Verify everything is healthy

```bash
docker compose -f docker-compose.app.yml ps
```

All services should show `healthy` or `running`. You can also run:

```bash
curl http://localhost/api/health
# Expected: {"status":"ok","uptime":...}
```

### Step 5 — Open the dashboard

Navigate to **http://localhost** in your browser and log in with the [demo credentials](#-default-demo-credentials).

### Common Docker Compose commands

```bash
# View logs for all services
docker compose -f docker-compose.app.yml logs -f

# View logs for a single service
docker compose -f docker-compose.app.yml logs -f backend

# Restart a single service
docker compose -f docker-compose.app.yml restart backend

# Stop and remove containers (keeps data volumes)
docker compose -f docker-compose.app.yml down

# Full reset — removes containers AND data volumes
docker compose -f docker-compose.app.yml down -v
```

---

## 💻 Local Development Setup

Use this approach when you want hot-reload for frontend/backend development.

### Prerequisites for local dev

- Node.js 20+ (`node --version`)
- Python 3.11+ (`python3 --version`)
- PostgreSQL 16 running locally (or via Docker)

### 1 — Start infrastructure dependencies only

```bash
# Start only PostgreSQL and Elasticsearch via Docker
docker compose -f docker-compose.app.yml up -d postgres elasticsearch
```

Wait ~30 seconds for Elasticsearch to initialise.

### 2 — Backend

```bash
cd backend
cp .env.example .env
# .env defaults connect to localhost:5432 and localhost:9200

npm install
npx prisma migrate dev --name init   # creates tables
npm run db:seed                      # seeds demo data and users
npm run dev                          # starts on http://localhost:4000
```

### 3 — AI Service

```bash
cd ai-service
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
# API docs: http://localhost:8000/docs
```

### 4 — SOAR Service

```bash
cd soar-service
pip install -r requirements.txt
uvicorn main:app --reload --port 8001
# API docs: http://localhost:8001/docs
```

### 5 — Frontend

```bash
cd frontend
cp .env.example .env
# VITE_API_BASE_URL defaults to "" (same origin, proxied via Vite)

npm install
npm run dev
# Dashboard: http://localhost:5173
```

---

## 🔑 Default Demo Credentials

These users are created automatically by the database seed (`npm run db:seed` or on first Docker start-up).

### Default Tenant

| Role | Email | Password | Access |
|------|-------|----------|--------|
| **Super Admin** | `superadmin@soc.local` | `SuperAdmin@123` | Full platform access |
| **Admin** | `admin@soc.local` | `Admin@123` | All features including correlation trigger |
| **Analyst** | `analyst@soc.local` | `Analyst@123` | Read + incident status updates |

### Demo Tenant (Acme Corp)

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@acme.local` | `AcmeAdmin@123` |
| Analyst | `analyst@acme.local` | `AcmeAnalyst@123` |

> **Tenant isolation:** Each tenant sees only its own alerts and incidents. Log in as `admin@soc.local` for the richest demo data.

---

## 🖥 Application Walkthrough

### Login Page (`/login`)

- JWT-based authentication with rate limiting (prevents brute-force on the demo itself)
- Supports optional `tenantSlug` for multi-tenant routing
- On success, a signed JWT token is stored locally and attached to all subsequent API calls

### Dashboard (`/`)

The main overview page loads three data sources in parallel:

| Widget | Data Source | What it shows |
|--------|------------|---------------|
| Backend status | `GET /api/health` | Service uptime and status |
| Open alerts count | `GET /api/alerts` | Total live alerts |
| Alert severity breakdown | `GET /api/alerts` | Critical / High / Medium / Low counts |
| Open incidents table | `GET /api/incidents?status=open&take=5` | Top 5 open incidents with AI risk scores |
| Recent alerts table | `GET /api/alerts` | Latest alerts with source and status |

### Incidents (`/incidents`)

The incident management centre:

- **Filterable table** — filter by severity, status (`open` / `investigating` / `resolved`), and rule type (`brute_force` / `traffic_spike`)
- **AI Risk Score** — colour-coded 0–100 score calculated by the AI anomaly detection service
- **AI Reason** — human-readable explanation (e.g. `login_attempt: observed=12.0, baseline=2.0±1.5, z-score=6.67, window=10min`)
- **Status workflow** — one-click `Investigate` → `Resolve` transitions (admin + analyst)
- **Run Correlation button** (admin only) — triggers a live scan of Elasticsearch for brute-force patterns and traffic spikes, creates new incidents in real time

### Logs (`/logs`)

Full-text search interface over Elasticsearch:

- **Query field** — Elasticsearch query string syntax (e.g. `ssh failed`, `rule.level:>10`)
- **Rule level filter** — filter by Wazuh rule severity level
- **Agent name filter** — filter by the source host/agent
- Returns up to 50 results per search, sorted by `@timestamp` descending

### SOAR Playbooks (`/playbooks`)

Two sections:

**Playbook Definitions** — lists all JSON-configured automated response playbooks loaded from `soar-service/playbooks/`. Each card shows:
  - Name and enabled/disabled status
  - Trigger rule type (e.g. `brute_force`) and minimum severity
  - Conditions (e.g. `eventCount >= 5`)
  - Actions (e.g. `block_ip`, `send_email`)

**Execution Audit Log** — every automated action taken by the SOAR engine, including playbook name, incident details, actions taken, status (`success` / `simulated` / `error`), and timestamp.

### Admin (`/admin`)

Tenant and user management for `admin` and `super_admin` roles.

---

## 📡 API Reference

All endpoints are prefixed with `/api/` and routed through Nginx.

### Health

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/health` | None | Backend liveness check |

### Authentication

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/login` | None | Login → returns JWT token |
| GET | `/api/auth/me` | JWT | Get current user profile |

**Login request body:**
```json
{
  "email": "admin@soc.local",
  "password": "Admin@123",
  "tenantSlug": "default"
}
```

### Alerts

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/alerts` | JWT (admin, analyst) | List alerts. Query: `severity`, `status`, `take`, `skip` |

### Incidents

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/incidents` | JWT (admin, analyst) | List incidents. Query: `severity`, `status`, `ruleType`, `from`, `to`, `take`, `skip` |
| POST | `/api/incidents/correlate` | JWT (admin) | Run correlation engine — scans ES and creates incidents |
| PATCH | `/api/incidents/:id` | JWT (admin, analyst) | Update incident status (`open` → `investigating` → `resolved`) |

### Logs

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/logs` | JWT (admin, analyst) | Search Elasticsearch. Query: `q`, `level`, `source`, `from`, `size`, `index` |

### AI Service (via backend proxy)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/ai/health` | JWT | AI service liveness |
| POST | `/api/ai/analyze` | JWT | Score an event for anomalies |

**Analyze request body:**
```json
{
  "event_type": "login_attempt",
  "value": 15,
  "window_minutes": 10,
  "source_ip": "203.0.113.42"
}
```

**Analyze response:**
```json
{
  "risk_score": 87,
  "is_anomaly": true,
  "severity": "critical",
  "reason": "login_attempt: observed=15.0, baseline=2.0±1.5, z-score=8.67, window=10min"
}
```

### SOAR Service (via backend proxy)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/soar/health` | JWT | SOAR service liveness |
| GET | `/api/soar/playbooks` | JWT | List all playbook definitions |
| POST | `/api/soar/trigger` | JWT | Manually trigger playbook evaluation for an incident |
| GET | `/api/soar/executions` | JWT | SOAR execution audit log |

---

## 🔄 Data Flow Explained

### Incident Detection Pipeline

```
Elasticsearch logs
        │
        ▼
  correlationService.js  (POST /api/incidents/correlate)
        │
        ├─── Rule 1: Brute Force
        │    • Queries ES for auth-failure events in last N minutes
        │    • Groups by source IP
        │    • Threshold ≥ 5 failures → creates/updates Incident
        │
        └─── Rule 2: Traffic Spike
             • Counts all events in last 5 minutes
             • Threshold > 500 events → creates/updates Incident
                        │
                        ▼
              AI Service: POST /analyze
              • Z-score against baseline (mean=2, std=1.5 for logins)
              • Returns risk_score (0–100) + severity + reason
                        │
                        ▼
              PostgreSQL: Incident record saved
              (with riskScore + aiReason from AI service)
                        │
                        ▼
              SOAR Service: POST /trigger (fire-and-forget)
              • Evaluates all enabled playbooks
              • Matches rule_type + min_severity + conditions
              • Executes actions: block_ip, send_email, create_ticket
              • Saves execution record to SQLite audit log
```

### Authentication Flow

```
Browser → POST /api/auth/login
        → backend validates email + bcrypt password
        → signs JWT (sub, email, role, tenantId)
        → returns token (8h expiry)

Subsequent requests:
  Authorization: Bearer <token>
        → requireAuth middleware decodes JWT
        → attaches req.user (including tenantId for data isolation)
```

---

## 🎬 Recommended Demo Script

Follow these steps for a polished, confident live demo. Each step is designed to showcase a distinct feature.

### Before the Demo (5 minutes before)

```bash
# 1. Ensure everything is running
docker compose -f docker-compose.app.yml up -d
docker compose -f docker-compose.app.yml ps   # all should be healthy

# 2. Confirm the UI loads
open http://localhost   # or http://<server-ip>

# 3. Verify health endpoint
curl http://localhost/api/health
```

---

### Step 1 — Login and Role-Based Access (2 min)

1. Open **http://localhost** — show the clean login page
2. Log in as **`admin@soc.local` / `Admin@123`**
3. Point out: *"The platform uses JWT-based authentication. Tokens expire after 8 hours. There's rate limiting on the login endpoint to prevent brute-force attacks on the SOC itself."*

---

### Step 2 — Dashboard Overview (3 min)

1. Land on the **Dashboard** — show the three status widgets at the top
2. Point to the alert severity breakdown: *"At a glance we can see how many critical, high, medium, and low alerts are open."*
3. Show the **Open Incidents table**: *"These are correlated incidents — not raw alerts. Each one has an AI-calculated risk score. The red `87` score means the AI service flagged this as statistically anomalous compared to our baseline."*
4. Scroll down to **Recent Alerts** and note the source column (Wazuh / Zabbix)

---

### Step 3 — Incident Management (5 min)

1. Navigate to **Incidents**
2. Show the full incidents table — point out columns: Severity, Title, Rule Type, Source IP, Host, Event Count, Risk Score, Status
3. **Filter demo:** Select *"Critical"* from the severity dropdown — table filters live without page reload
4. **AI Reason:** Point to the italic text under an incident title — *"This is the AI service explaining why it flagged this. It shows the observed value, baseline, and z-score."*
5. **Status workflow:** Click **Investigate** on an open incident → status badge changes from blue to purple — *"Analysts mark incidents as under investigation so the team knows it's being handled."*
6. **Run Correlation:** Click the **Run Correlation** button — *"This triggers a live scan of our Elasticsearch log store. The engine applies two rules: brute-force detection groups failed auth events by source IP, and traffic spike detection counts total event volume. New incidents appear immediately."*

---

### Step 4 — AI Anomaly Detection (3 min)

1. Open a terminal (or use the browser's dev tools Network tab for the AI call)
2. Show a live API call to demonstrate the AI service:

```bash
curl -X POST http://localhost/ai/analyze \
  -H "Content-Type: application/json" \
  -d '{"event_type":"login_attempt","value":20,"window_minutes":10,"source_ip":"203.0.113.42"}'
```

Expected response:
```json
{
  "risk_score": 100,
  "is_anomaly": true,
  "severity": "critical",
  "reason": "login_attempt: observed=20.0, baseline=2.0±1.5, z-score=12.00, window=10min"
}
```

3. Explain: *"The AI service uses statistical Z-score analysis. Normal login activity averages 2 attempts with a standard deviation of 1.5. Twenty failed logins in 10 minutes is 12 standard deviations above baseline — clearly anomalous."*

---

### Step 5 — Log Search (2 min)

1. Navigate to **Logs**
2. Enter `ssh` in the search box and click **Search**
3. Show the results: timestamp, agent name, rule level, and message columns
4. Try filtering by rule level `10` — *"Rule level 10+ in Wazuh indicates high-severity security events."*
5. Point out: *"This is a direct window into our Elasticsearch log store, the same data the correlation engine analyses."*

---

### Step 6 — SOAR Playbooks (4 min)

1. Navigate to **SOAR Playbooks**
2. Show the **Playbook Definitions** section:
   - **Brute Force – Block Source IP**: *"When a brute-force incident with ≥ 5 events is detected, this playbook automatically blocks the source IP and sends an email alert."*
   - **Traffic Spike Alert**: *"When unusual traffic volume is detected, this fires an email notification."*
3. Show the **Execution Audit Log** — every automated action the SOAR engine has taken, with playbook name, incident, actions, status, and timestamp
4. Emphasise: *"This gives the SOC team a complete audit trail of every automated response action."*

---

### Step 7 — Multi-Tenancy (2 min)

1. Log out
2. Log in as **`admin@acme.local` / `AcmeAdmin@123`**
3. Show the dashboard — different incidents belonging to the Acme Corp tenant
4. *"The platform is multi-tenant. Each tenant's data is completely isolated. The same platform can serve multiple clients or business units."*

---

### Closing Talking Points

- **"The full stack runs in 7 Docker containers — one command to start the entire platform."**
- **"The correlation engine, AI service, and SOAR engine work together: logs → detection → AI scoring → automated response."**
- **"Phase 2 will add Logstash enrichment and advanced threat intelligence correlation."**
- **"The architecture is cloud-ready — Terraform scripts for AWS EC2 deployment are included."**

---

## ✅ Pre-Demo Checklist

Run through this checklist at least 10 minutes before the demo.

```
□ docker compose -f docker-compose.app.yml ps
    → All 7 services show "healthy" or "running"

□ curl http://localhost/api/health
    → {"status":"ok",...}

□ Open http://localhost in browser
    → Login page loads with no console errors

□ Log in as admin@soc.local / Admin@123
    → Dashboard loads with alerts and incidents visible

□ Navigate to Incidents page
    → Incidents table is populated (at least 3–4 incidents)

□ Click "Run Correlation"
    → Green success banner appears

□ Navigate to SOAR Playbooks
    → At least 2 playbooks listed

□ Log out and log in as admin@acme.local / AcmeAdmin@123
    → Different incidents visible (tenant isolation confirmed)

□ Open a spare terminal with logs ready:
    docker compose -f docker-compose.app.yml logs -f backend
```

---

## 🔧 Troubleshooting

### Services not starting / unhealthy

```bash
# Check logs for a specific service
docker compose -f docker-compose.app.yml logs backend
docker compose -f docker-compose.app.yml logs elasticsearch

# Restart unhealthy service
docker compose -f docker-compose.app.yml restart backend
```

### Elasticsearch fails to start (exit code 137 — OOM)

Elasticsearch requires at least 2 GB of RAM. Increase Docker Desktop memory allocation to ≥ 4 GB in Docker Desktop → Settings → Resources.

Alternatively, reduce the JVM heap in `.env`:
```dotenv
ES_JAVA_OPTS=-Xms256m -Xmx256m
```

### Dashboard shows "Failed to load dashboard data"

The backend is not reachable. Check:
```bash
docker compose -f docker-compose.app.yml logs backend
curl http://localhost/api/health
```

### Login returns 401 "Invalid credentials"

Seed data may not have run. Force re-seed:
```bash
docker compose -f docker-compose.app.yml exec backend npm run db:seed
```

### "No incidents found" after running correlation

The correlation engine reads from Elasticsearch. If there are no logs indexed, no incidents are created by the correlation run. The **seed data** (sample incidents) was loaded by the database seed — if you see no incidents, re-run the seed:
```bash
docker compose -f docker-compose.app.yml exec backend npm run db:seed
```

### Port 80 already in use

Another process is using port 80. Change the public port in `.env`:
```dotenv
APP_PORT=8080
```
Then restart: `docker compose -f docker-compose.app.yml up -d`

### Full reset (wipe all data and start fresh)

```bash
docker compose -f docker-compose.app.yml down -v
docker compose -f docker-compose.app.yml up -d --build
```

---

## 🔒 Security Features

- ✅ JWT authentication with configurable expiry (default 8 h)
- ✅ bcrypt password hashing (cost factor 10)
- ✅ Rate limiting on login and authenticated routes
- ✅ Multi-tenant data isolation (tenantId scoped queries throughout)
- ✅ Role-based access control (`super_admin` / `admin` / `analyst`)
- ✅ Elasticsearch X-Pack security enabled
- ✅ Network isolation — all services communicate on a private Docker bridge network
- ✅ Nginx reverse proxy — only port 80 is exposed publicly

---

## 🏛 Legacy Infrastructure Stack (Zabbix / Wazuh)

The `docker-compose.yml` (not `docker-compose.app.yml`) contains the original infrastructure monitoring stack:

| Component | Tool | Purpose |
|-----------|------|---------|
| Infrastructure Monitoring | Zabbix 6.4 | CPU, Memory, Disk, Network |
| SIEM | Wazuh 4.7 | Security log collection & analysis |
| Data Store | Elasticsearch 8.11 | Centralised log storage |
| Visualisation | Kibana 8.11 | Security dashboards |
| Database | PostgreSQL 15 | Zabbix backend |
| Alerting | Python 3.11 | Email alerts via SMTP |

This stack is the data source for the application stack — Wazuh indexes security logs into Elasticsearch, which the backend's correlation engine queries.

| Dashboard | URL | Credentials |
|-----------|-----|-------------|
| Kibana | http://localhost:5601 | elastic / `<ELASTIC_PASSWORD>` |
| Zabbix | http://localhost:8080 | Admin / zabbix |

See [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) for full Zabbix/Wazuh deployment instructions.

---

## ☁️ Cloud Deployment (AWS)

Infrastructure-as-Code with Terraform provisions an EC2 instance ready for the full stack:

```bash
cd terraform/

terraform init

terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

After `apply` completes, the output includes the public IP and dashboard URLs.

---

## 📁 Repository Structure

```
soc-platform-phase1/
├── docker-compose.app.yml          # ⭐ Application stack (use this for demo)
├── docker-compose.yml              # Legacy infrastructure stack (Zabbix/Wazuh)
├── .env.example                    # Environment variable template
├── nginx/
│   └── nginx.conf                  # Reverse proxy routing config
├── backend/                        # Node.js / Express REST API
│   ├── Dockerfile
│   ├── prisma/
│   │   ├── schema.prisma           # Data models (Tenant, User, Alert, Incident, LogMeta)
│   │   └── seed.js                 # Demo data seeder
│   └── src/
│       ├── server.js               # Express app entry point
│       ├── routes/                 # auth, alerts, logs, incidents, ai, soar, tenants
│       ├── middleware/             # JWT auth, rate limiting
│       ├── services/
│       │   └── correlationService.js  # Correlation engine (brute_force + traffic_spike)
│       └── lib/                    # Prisma client, ES client, AI client, SOAR client
├── frontend/                       # React 18 + Vite + Tailwind
│   └── src/
│       ├── pages/                  # LoginPage, DashboardPage, IncidentsPage, LogsPage,
│       │                           #   PlaybooksPage, AdminPage
│       └── api/client.js           # Axios instance with JWT interceptor
├── ai-service/                     # Python FastAPI anomaly detection
│   ├── main.py                     # FastAPI app + /health /analyze endpoints
│   └── detector.py                 # Z-score engine with configurable baselines
├── soar-service/                   # Python FastAPI SOAR engine
│   ├── main.py                     # FastAPI app + /health /playbooks /trigger /executions
│   ├── engine.py                   # Playbook evaluation + action dispatch
│   ├── actions.py                  # Action implementations (block_ip, send_email, etc.)
│   ├── db.py                       # SQLite audit log
│   └── playbooks/
│       ├── brute_force_block_ip.json
│       └── traffic_spike_alert.json
├── alerting/                       # Legacy Python SMTP alerting service
├── config/                         # Zabbix, Wazuh, Elasticsearch, Kibana configs
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SETUP_GUIDE.md
│   ├── RUNBOOKS.md
│   ├── API_INTEGRATION.md
│   └── POC_APPLICATION_DOCUMENT.md
├── scripts/                        # Deployment and health-check scripts
├── terraform/                      # AWS EC2 IaC
└── tests/                          # API integration tests
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Detailed system design and data flow diagrams |
| [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | Step-by-step deployment guide (incl. Zabbix/Wazuh) |
| [RUNBOOKS.md](docs/RUNBOOKS.md) | Operations playbooks and incident response procedures |
| [API_INTEGRATION.md](docs/API_INTEGRATION.md) | Full REST API reference |
| [POC_APPLICATION_DOCUMENT.md](docs/POC_APPLICATION_DOCUMENT.md) | Proof-of-concept overview |

---

## 🗺 Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **Phase 1** | Foundation: Full-stack SOC dashboard, JWT auth, AI anomaly detection, SOAR playbooks, multi-tenancy | ✅ **Current** |
| **Phase 2** | Analytics: Logstash enrichment, advanced correlation rules, threat intelligence feeds | 🔜 Planned |
| **Phase 3** | Scale: ML-based anomaly detection, MITRE ATT&CK mapping, compliance reporting | 🔜 Planned |

---

## License

MIT License — see [LICENSE](LICENSE) for details.
