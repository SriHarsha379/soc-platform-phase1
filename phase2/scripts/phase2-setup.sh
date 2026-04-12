#!/usr/bin/env bash
# =============================================================================
# phase2-setup.sh - Main setup orchestrator for Phase 2
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
KIBANA_HOST="${KIBANA_HOST:-localhost}"
KIBANA_PORT="${KIBANA_PORT:-5601}"
WAZUH_CONTAINER="${WAZUH_CONTAINER:-wazuh-manager}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
section() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }

# ── Make all scripts executable ───────────────────────────────────────────────
find "${PHASE2_DIR}" -name "*.sh" -exec chmod +x {} \;
find "${PHASE2_DIR}" -name "*.py" -exec chmod +x {} \;

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     SOC Platform Phase 2 - Full Setup Orchestration          ║"
echo "║     Data Analytics & Log Correlation Layer                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  ES:     http://${ES_HOST}:${ES_PORT}"
echo "  Kibana: http://${KIBANA_HOST}:${KIBANA_PORT}"
echo "  Start:  $(date)"
echo ""

# ── Step 1: Deploy Elasticsearch Indices ──────────────────────────────────────
section "Step 1: Elasticsearch Indices & ILM"
bash "${SCRIPT_DIR}/deploy-indices.sh" || warn "Index deployment had warnings. Continuing..."

# ── Step 2: Deploy Wazuh Rules ────────────────────────────────────────────────
section "Step 2: Wazuh Correlation Rules"
bash "${SCRIPT_DIR}/deploy-wazuh-rules.sh" || warn "Wazuh rule deployment had warnings. Continuing..."

# ── Step 3: Setup Metrics Pipeline ────────────────────────────────────────────
section "Step 3: Metrics Integration"
bash "${SCRIPT_DIR}/setup-metrics.sh" || warn "Metrics setup had warnings. Continuing..."

# ── Step 4: Import Kibana Dashboards ──────────────────────────────────────────
section "Step 4: Kibana Dashboards"
bash "${SCRIPT_DIR}/setup-dashboards.sh" || warn "Dashboard setup had warnings. Continuing..."

# ── Step 5: Health Check ──────────────────────────────────────────────────────
section "Step 5: Health Verification"
bash "${SCRIPT_DIR}/health-check.sh" || warn "Some health checks failed. Review the output above."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Phase 2 Setup Complete!                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
info "Kibana Dashboards: http://${KIBANA_HOST}:${KIBANA_PORT}/app/dashboards"
info "Elasticsearch:     http://${ES_HOST}:${ES_PORT}/_cluster/health"
echo ""
info "Next steps:"
echo "  1. Configure Zabbix exporter: edit phase2/metrics-integration/zabbix-exporter/config.yaml"
echo "  2. Start metrics exporter:   systemctl start soc-metrics-exporter"
echo "  3. Validate metrics:         bash phase2/scripts/validate-correlation.sh"
echo "  4. Run benchmark:            bash phase2/scripts/performance-benchmark.sh"
echo "  5. Review docs:              phase2/docs/PHASE2_OVERVIEW.md"
echo ""
