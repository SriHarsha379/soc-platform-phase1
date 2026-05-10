# SOC Platform Proof of Concept Document

## 1. Executive Summary

This repository contains a proof-of-concept Security Operations Center (SOC) platform built with open-source components and a custom application layer. The solution combines infrastructure monitoring, security event ingestion, centralized search, incident correlation, AI-assisted anomaly scoring, and SOAR automation in a single deployable stack.

The platform is designed to demonstrate how a lean SOC can move from raw telemetry to operational response:

- **Zabbix** monitors infrastructure health.
- **Wazuh** collects and analyzes security events.
- **Elasticsearch + Kibana** centralize search and dashboards.
- **A custom backend and frontend** provide analyst workflows.
- **AI and SOAR microservices** enrich detections and automate actions.

The repository also includes a **Phase 2 extension** that expands the platform with advanced analytics, additional correlation logic, dashboard assets, and scaling guidance.

---

## 2. POC Goals

The application demonstrates the following capabilities:

1. **Centralized SOC visibility** across infrastructure and security telemetry.
2. **Role-based analyst workflows** through a dedicated web application.
3. **Incident generation from correlated events** rather than only raw alerts.
4. **AI-assisted prioritization** using anomaly scoring.
5. **SOAR-driven response automation** through playbooks.
6. **Multi-tenant readiness** for managed SOC or segmented internal operations.
7. **Deployment flexibility** through Docker Compose, scripts, and Terraform assets.

---

## 3. Solution Scope

### Core Phase 1 Scope

- Infrastructure monitoring with Zabbix
- SIEM ingestion and rule-based detection with Wazuh
- Centralized storage and search with Elasticsearch
- Visualization with Kibana
- Email alerting service
- Full-stack SOC dashboard application
- Incident correlation engine
- AI anomaly detection microservice
- SOAR playbook execution microservice

### Phase 2 Scope

- Elasticsearch optimization and lifecycle management
- Additional correlation rules and logic
- Metrics export from Zabbix into Elasticsearch
- Kibana dashboard assets
- Advanced field mapping, scaling, and troubleshooting guidance

---

## 4. High-Level Architecture

### Data Sources

- Monitored hosts run **Zabbix agents** for health metrics.
- Hosts and systems generate logs consumed by **Wazuh agents**.

### Platform Core

- **Zabbix Server + PostgreSQL** manage monitoring state and triggers.
- **Wazuh Manager** processes security events and rules.
- **Elasticsearch** stores searchable alerts and logs.
- **Kibana** provides operational dashboards.

### Application Layer

- **Express backend** exposes APIs for auth, alerts, logs, incidents, AI, SOAR, and tenants.
- **React frontend** provides dashboards for analysts and administrators.
- **FastAPI AI service** scores anomalies.
- **FastAPI SOAR service** executes playbooks and stores execution history.

### Access Layer

- **Nginx** routes browser traffic to the frontend and API requests to backend and microservices.

---

## 5. Repository Breakdown

| Area | Purpose |
|---|---|
| `backend/` | Express API, Prisma data layer, JWT auth, correlation logic |
| `frontend/` | React SOC dashboard UI |
| `ai-service/` | FastAPI anomaly detection service |
| `soar-service/` | FastAPI SOAR playbook engine |
| `alerting/` | Python email alert polling service |
| `config/` | Zabbix, Wazuh, Elasticsearch, Kibana, and alerting configuration |
| `docs/` | Architecture, setup, runbooks, API, and this POC document |
| `scripts/` | Automated deployment and health-check scripts |
| `phase2/` | Advanced analytics, dashboards, index strategy, and correlation assets |
| `terraform/` | Infrastructure-as-code assets for cloud deployment |
| `tests/` | Shell-based integration checks for core platform services |

---

## 6. Main Application Capabilities

### 6.1 Authentication and Access Control

The backend uses JWT-based authentication and role-aware authorization. Supported roles are:

- `analyst`
- `admin`
- `super_admin`

The implementation also supports **multi-tenancy**:

- tenants are stored in the Prisma schema
- users belong to a tenant
- login supports an optional `tenantSlug`
- JWT tokens include tenant context
- tenant-specific data access is enforced in backend routes

### 6.2 Alerts and Log Visibility

Analysts can:

- retrieve alerts stored in PostgreSQL
- search Elasticsearch-backed logs
- filter logs by query, level, and agent name
- review recent activity from a single SOC dashboard

### 6.3 Incident Correlation

The platform does more than display raw alerts. It generates incidents by applying correlation rules over recent Elasticsearch data. The current implementation includes:

- **Brute-force detection** based on repeated failed authentication activity from the same IP
- **Traffic spike detection** based on unusually high event volume in a short window

Incidents carry:

- severity
- source IP
- affected host
- event count
- time window context
- optional AI-derived risk score and reason

### 6.4 AI-Assisted Analysis

The AI service provides lightweight statistical anomaly detection. It accepts:

- `event_type`
- `value`
- `window_minutes`
- optional source context

It returns:

- `risk_score`
- `is_anomaly`
- `severity`
- `reason`

This is used by the correlation engine to enrich incidents with better prioritization context.

### 6.5 SOAR Playbooks

The SOAR service exposes playbook definitions and an execution log. Matching incidents can trigger automated actions such as:

- blocking IPs
- sending email notifications
- sending Telegram notifications

This allows the POC to demonstrate a full path from detection to response.

### 6.6 Administration

Administrative workflows include:

- tenant creation
- per-tenant user management
- user deletion safeguards
- admin vs super-admin permission separation

This makes the POC suitable for demonstrating internal segmentation or MSSP-style operations.

---

## 7. Frontend User Experience

The React application provides the following user-facing pages:

| Page | Purpose |
|---|---|
| Login | JWT sign-in with optional tenant slug |
| Dashboard | Health widgets, recent alerts, and open incident summary |
| Logs | Elasticsearch-backed log search and filtering |
| Incidents | Incident review, filtering, status management, and manual correlation trigger |
| Playbooks | SOAR playbook catalog and execution audit log |
| Admin | Tenant and user management |

The frontend acts as the operator console for the custom SOC application layer.

---

## 8. Backend Service Responsibilities

| API Area | Responsibility |
|---|---|
| `/api/auth` | Login and current-user identity |
| `/api/alerts` | Alert retrieval from Prisma/PostgreSQL |
| `/api/logs` | Elasticsearch querying |
| `/api/incidents` | Incident listing, status updates, and correlation trigger |
| `/api/ai` | AI service health and analysis proxy |
| `/api/soar` | SOAR service health, playbooks, and executions |
| `/api/tenants` | Tenant and tenant-user administration |
| `/api/health` | Backend liveness check |

Additional backend characteristics:

- Prisma with PostgreSQL for application data
- rate limiting for login and authenticated routes
- role-based middleware
- tenant-scoped data access
- non-blocking AI and SOAR integrations within the correlation flow

---

## 9. Supporting Platform Components

### Zabbix

Used for infrastructure monitoring, trigger generation, and operational visibility over:

- CPU
- memory
- disk
- network
- host availability

### Wazuh

Used for SIEM and security event processing, including:

- SSH brute-force monitoring
- privilege escalation indicators
- file integrity monitoring
- root login detection
- other rule-driven security events

### Elasticsearch and Kibana

Used for:

- log storage
- alert search
- dashboard visualization
- retention and lifecycle management

### Alerting Service

The Python alerting service polls Elasticsearch and sends SMTP email alerts for high-value operational and security conditions.

---

## 10. End-to-End Operational Flow

1. An endpoint generates infrastructure metrics and security logs.
2. Zabbix and Wazuh ingest the relevant telemetry.
3. Wazuh detections and related events are indexed into Elasticsearch.
4. The backend exposes alerts, logs, and incidents to the frontend.
5. The correlation service analyzes recent events and creates or updates incidents.
6. The AI service optionally enriches incidents with anomaly-based risk scoring.
7. The SOAR service optionally triggers playbooks for matching incidents.
8. Analysts use the frontend to investigate, track, and resolve incidents.

This is the central proof point of the application: **telemetry → detection → correlation → prioritization → response**.

---

## 11. Deployment Model

The repository supports multiple deployment paths.

### Option A: Core SOC Stack

`docker-compose.yml` provisions the foundational SOC services such as Zabbix, Wazuh, Elasticsearch, Kibana, and alerting.

### Option B: Application Stack

`docker-compose.app.yml` provisions:

- PostgreSQL
- Elasticsearch
- backend
- frontend
- AI service
- SOAR service
- Nginx reverse proxy

### Option C: Scripted Installation

The `scripts/` directory provides deployment and validation helpers, including:

- initial setup
- Zabbix deployment
- Wazuh deployment
- alert configuration
- health checks

### Option D: Cloud Infrastructure

The `terraform/` directory enables infrastructure provisioning for cloud-based deployment scenarios.

---

## 12. Security and Operational Readiness

The POC demonstrates several security-conscious design elements:

- JWT-based API authentication
- RBAC-aware route protection
- multi-tenant data separation
- rate limiting for login and authenticated endpoints
- Elasticsearch security support
- configurable TLS posture
- isolated service networking in Docker
- incident and automation audit visibility

Operationally, the repo also includes:

- setup documentation
- API reference
- runbooks
- shell-based integration checks
- health endpoints across services

---

## 13. Phase 2 Value

Phase 2 meaningfully extends the proof of concept by showing how the platform can evolve beyond a baseline SOC:

- optimized Elasticsearch indexing and ILM
- extended Wazuh rules and decoders
- Zabbix-to-Elasticsearch metric export
- richer Kibana dashboards
- broader correlation coverage
- scaling and troubleshooting guidance

This makes the repository useful not only as a demo, but as a staged blueprint for future maturity.

---

## 14. Strengths of This Proof of Concept

- Combines open-source SOC tooling with a custom analyst-facing application
- Covers both infrastructure monitoring and security operations
- Demonstrates incident correlation instead of raw alert viewing only
- Introduces AI-assisted prioritization in a practical, lightweight form
- Demonstrates response automation through playbooks
- Includes multi-tenant concepts that are often missing from early SOC demos
- Provides documentation, scripts, and infrastructure assets for reproducibility

---

## 15. Current POC Boundaries

This repository is strong as a functional proof of concept, but some areas are still intentionally lightweight:

- backend automated tests are not yet implemented
- AI logic is statistical rather than model-heavy
- current correlation rules are intentionally limited and extensible
- production hardening requires additional secrets management, TLS, monitoring, and operational controls

These limits are appropriate for a POC and provide a clear path for future enhancement.

---

## 16. Recommended Use of This Document

This document can be used as:

- a project summary for stakeholders
- a demo handout for reviewers
- a technical overview for onboarding
- a bridge between the repository structure and the detailed docs already present

For deeper technical details, refer to:

- `docs/ARCHITECTURE.md`
- `docs/SETUP_GUIDE.md`
- `docs/RUNBOOKS.md`
- `docs/API_INTEGRATION.md`
- `phase2/docs/PHASE2_OVERVIEW.md`

---

## 17. Conclusion

The application in this repository is a solid SOC proof of concept that demonstrates how monitoring, SIEM, search, visualization, incident management, anomaly scoring, and automated response can be combined into a single platform. It is practical enough to showcase real workflows, modular enough to extend, and documented well enough to serve as the foundation for subsequent phases.
