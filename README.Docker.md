# Docker Deployment – SOC Platform

This guide covers building and running the full SOC application stack using
`docker-compose.app.yml`.

## Services included

| Service | Container | Port (internal) | Description |
|---|---|---|---|
| Nginx | `soc-nginx` | **80** (public) | Reverse proxy / entry point |
| React frontend | `soc-frontend` | 80 | Vite build served by Nginx |
| Express backend | `soc-backend` | 4000 | REST API + Prisma ORM |
| PostgreSQL | `soc-postgres` | 5432 | Application database |
| Elasticsearch | `soc-elasticsearch` | 9200 | Log & alert storage |
| AI service | `soc-ai` | 8000 | Anomaly detection (FastAPI) |
| SOAR service | `soc-soar` | 8001 | Playbook automation (FastAPI) |

## Routing (via Nginx reverse proxy)

| Path | Upstream |
|---|---|
| `/api/*` | `soc-backend:4000` |
| `/ai/*` | `soc-ai:8000` |
| `/soar/*` | `soc-soar:8001` |
| `/*` | `soc-frontend:80` (SPA) |

## Prerequisites

- Docker ≥ 24 and Docker Compose v2 (`docker compose`)
- At least 2 GB free RAM (Elasticsearch needs headroom)

## Quick start

```bash
# 1. Copy and customise environment variables
cp .env.example .env
# Edit .env – at minimum set JWT_SECRET and SOC_DB_PASSWORD

# 2. Build all images
docker compose -f docker-compose.app.yml build

# 3. Start the stack (detached)
docker compose -f docker-compose.app.yml up -d

# 4. Seed the database (first run only)
docker compose -f docker-compose.app.yml exec backend node prisma/seed.js

# 5. Open the dashboard
open http://localhost        # or the value of APP_PORT in your .env
```

## Common commands

```bash
# View live logs for all services
docker compose -f docker-compose.app.yml logs -f

# View logs for a single service
docker compose -f docker-compose.app.yml logs -f backend

# Restart a single service (e.g. after a config change)
docker compose -f docker-compose.app.yml restart backend

# Rebuild and restart a single service
docker compose -f docker-compose.app.yml up -d --build backend

# Rebuild everything
docker compose -f docker-compose.app.yml build --no-cache

# Stop the stack (data volumes preserved)
docker compose -f docker-compose.app.yml down

# Stop and remove all data volumes (destructive)
docker compose -f docker-compose.app.yml down -v
```

## Default seed accounts

| Email | Password | Role | Tenant |
|---|---|---|---|
| `superadmin@soc.local` | `Admin1234!` | super_admin | default |
| `admin@soc.local` | `Admin1234!` | admin | default |
| `admin@acme.local` | `Admin1234!` | admin | acme |
| `analyst@acme.local` | `Analyst1234!` | analyst | acme |

> ⚠️ Change all passwords before deploying to a public environment.

## Environment variables reference

See `.env.example` for the full list.  Key variables for the app stack:

| Variable | Default | Description |
|---|---|---|
| `APP_PORT` | `80` | Host port exposed by Nginx |
| `JWT_SECRET` | *(required)* | Secret key for JWT signing |
| `SOC_DB_USER` | `soc_user` | PostgreSQL username |
| `SOC_DB_PASSWORD` | `soc_password` | PostgreSQL password |
| `SOC_DB_NAME` | `soc_db` | PostgreSQL database name |
| `ELASTIC_PASSWORD` | `elastic_secure_password` | Elasticsearch password |
| `ES_JAVA_OPTS` | `-Xms512m -Xmx512m` | Elasticsearch JVM heap |

## Architecture

```
Browser
  │
  ▼
Nginx :80  ──────────────────────────────────────────────────
  │ /api/*            │ /ai/*          │ /soar/*    │ /
  ▼                   ▼                ▼            ▼
soc-backend:4000   soc-ai:8000   soc-soar:8001  soc-frontend:80
  │
  ├── PostgreSQL:5432  (Prisma ORM)
  └── Elasticsearch:9200 (log queries)
```
