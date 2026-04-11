#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Zabbix Deployment Script
# Usage: ./scripts/deploy-zabbix.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ZABBIX]${NC} $*"; }
warn() { echo -e "${YELLOW}[ZABBIX]${NC} $*"; }
error(){ echo -e "${RED}[ZABBIX]${NC} $*" >&2; }

cd "$PROJECT_ROOT"

# ── Load environment ───────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

log "Starting Zabbix deployment …"

# ── Start Zabbix services ──────────────────────────────────────────────────────
log "Starting Zabbix database …"
docker-compose up -d zabbix-db

log "Waiting for PostgreSQL to be ready …"
for i in $(seq 1 30); do
    if docker-compose exec -T zabbix-db pg_isready -U "${POSTGRES_USER:-zabbix}" > /dev/null 2>&1; then
        log "PostgreSQL is ready."
        break
    fi
    if [[ $i -eq 30 ]]; then
        error "PostgreSQL did not start in time."
        exit 1
    fi
    sleep 5
done

log "Starting Zabbix Server …"
docker-compose up -d zabbix-server

log "Starting Zabbix Web Frontend …"
docker-compose up -d zabbix-web

log "Starting Zabbix Agent …"
docker-compose up -d zabbix-agent

# ── Wait for Zabbix Web to be ready ───────────────────────────────────────────
log "Waiting for Zabbix Web to be ready …"
for i in $(seq 1 24); do
    if curl -sf "http://localhost:8080/ping" > /dev/null 2>&1; then
        log "Zabbix Web is ready at http://localhost:8080"
        break
    fi
    if [[ $i -eq 24 ]]; then
        warn "Zabbix Web did not respond in 2 minutes. It may still be initializing."
    fi
    sleep 5
done

# ── Import host templates via Zabbix API ───────────────────────────────────────
log "Importing host groups and templates via Zabbix API …"

ZABBIX_URL="http://localhost:8080"
ZABBIX_USER="Admin"
ZABBIX_PASS="zabbix"

# Wait a bit more for the API to fully initialize
sleep 10

# Get auth token
TOKEN_RESPONSE=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"${ZABBIX_USER}\",\"password\":\"${ZABBIX_PASS}\"},\"id\":1}" \
    "${ZABBIX_URL}/api_jsonrpc.php" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

if [[ -z "$AUTH_TOKEN" ]]; then
    warn "Could not obtain Zabbix API token – host configuration will be skipped."
    warn "You can configure manually at http://localhost:8080 (Admin/zabbix)"
else
    log "Successfully authenticated with Zabbix API."

    # Create host group
    curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.create\",\"params\":{\"name\":\"SOC-Monitored-Servers\"},\"auth\":\"${AUTH_TOKEN}\",\"id\":2}" \
        "${ZABBIX_URL}/api_jsonrpc.php" > /dev/null 2>&1 || warn "Host group may already exist."

    log "Host group 'SOC-Monitored-Servers' created."
fi

log "Zabbix deployment complete."
log "Access: http://localhost:8080 (Admin / zabbix)"
warn "IMPORTANT: Change the default Zabbix admin password immediately!"
