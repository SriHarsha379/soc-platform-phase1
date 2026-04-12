#!/usr/bin/env bash
# =============================================================================
# deploy-indices.sh - Deploy all Phase 2 Elasticsearch index templates
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

echo ""
echo "============================================================"
echo "  Phase 2 - Deploy Elasticsearch Index Templates + ILM"
echo "  $(date)"
echo "============================================================"
echo ""

exec bash "${PHASE2_DIR}/elasticsearch/scripts/init-indices.sh"
