#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Initial Setup Script
# Usage: ./scripts/init-setup.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error(){ echo -e "${RED}[ERROR]${NC} $*" >&2; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }

# ── Prerequisites check ────────────────────────────────────────────────────────
step "Checking prerequisites …"

for cmd in docker docker-compose curl; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done
log "All prerequisites satisfied."

# ── Environment file setup ─────────────────────────────────────────────────────
step "Setting up environment file …"
cd "$PROJECT_ROOT"

if [[ ! -f .env ]]; then
    cp .env.example .env
    warn ".env file created from template. Edit it with your actual values before proceeding."
    warn "  → nano .env"
    read -rp "Press Enter when you have reviewed/updated .env to continue …"
else
    log ".env already exists – using existing configuration."
fi

# shellcheck disable=SC1091
source .env

# ── System requirements ────────────────────────────────────────────────────────
step "Configuring system requirements for Elasticsearch …"

# Increase virtual memory map count (required by Elasticsearch)
if [[ "$(sysctl -n vm.max_map_count)" -lt 262144 ]]; then
    log "Setting vm.max_map_count=262144 …"
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
else
    log "vm.max_map_count already set correctly."
fi

# Increase ulimit for open files
if [[ "$(ulimit -n)" -lt 65536 ]]; then
    warn "Open file limit is low. Consider adding to /etc/security/limits.conf:"
    warn "  * soft nofile 65536"
    warn "  * hard nofile 65536"
fi

# ── Deploy services ────────────────────────────────────────────────────────────
step "Deploying SOC Platform services …"

"$SCRIPT_DIR/deploy-zabbix.sh"
"$SCRIPT_DIR/deploy-wazuh.sh"

step "Starting all services …"
docker-compose up -d

# ── Wait for services ──────────────────────────────────────────────────────────
step "Waiting for services to become healthy …"

wait_for_service() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log "$name is ready."
            return 0
        fi
        echo -n "."
        sleep 10
        ((attempt++))
    done
    warn "$name did not become ready in time. Check: docker-compose logs $name"
    return 1
}

wait_for_service "Elasticsearch" "http://localhost:9200" 30 || true
wait_for_service "Kibana"         "http://localhost:5601/api/status" 30 || true
wait_for_service "Zabbix Web"    "http://localhost:8080/ping" 20 || true

# ── Configure alerts ───────────────────────────────────────────────────────────
step "Configuring alerting system …"
"$SCRIPT_DIR/configure-alerts.sh" || warn "Alert configuration had warnings – check output above."

# ── Summary ────────────────────────────────────────────────────────────────────
step "SOC Platform is ready!"
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │            SOC PLATFORM - ACCESS DETAILS            │"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │  Kibana Dashboard  : http://localhost:5601           │"
echo "  │    User: elastic   Pass: (from .env)                 │"
echo "  │                                                      │"
echo "  │  Zabbix Dashboard  : http://localhost:8080           │"
echo "  │    User: Admin     Pass: zabbix                      │"
echo "  │                                                      │"
echo "  │  Elasticsearch API : http://localhost:9200           │"
echo "  │  Wazuh API         : https://localhost:55000         │"
echo "  │    User: wazuh-wui Pass: (from .env)                 │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
log "Run './scripts/health-check.sh' to verify all services."
