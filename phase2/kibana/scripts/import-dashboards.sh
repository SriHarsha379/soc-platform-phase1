#!/usr/bin/env bash
# =============================================================================
# import-dashboards.sh - Import Phase 2 Kibana dashboards
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIBANA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

KIBANA_HOST="${KIBANA_HOST:-localhost}"
KIBANA_PORT="${KIBANA_PORT:-5601}"
KIBANA_URL="http://${KIBANA_HOST}:${KIBANA_PORT}"
KIBANA_USER="${ELASTIC_USERNAME:-elastic}"
KIBANA_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${KIBANA_USER}:${KIBANA_PASS}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

wait_for_kibana() {
  info "Waiting for Kibana at ${KIBANA_URL}..."
  for i in $(seq 1 24); do
    if curl -sf ${AUTH} "${KIBANA_URL}/api/status" | python3 -c "import sys,json; s=json.load(sys.stdin); sys.exit(0 if s.get('status',{}).get('overall',{}).get('level','') in ('available','degraded') else 1)" 2>/dev/null; then
      info "Kibana is ready."
      return 0
    fi
    echo -n "."
    sleep 5
  done
  error "Kibana did not become ready within 2 minutes."
  exit 1
}

import_ndjson() {
  local file="$1"
  local name
  name="$(basename "${file}")"
  info "Importing: ${name}"
  local result
  result=$(curl -sf ${AUTH} -X POST "${KIBANA_URL}/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" \
    -F "file=@${file}" 2>&1)
  local success
  success=$(echo "${result}" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('success','false'))" 2>/dev/null || echo "false")
  if [[ "${success}" == "True" ]] || [[ "${success}" == "true" ]]; then
    info "  ✓ Imported: ${name}"
  else
    warn "  ⚠ Import result for ${name}: ${result}"
  fi
}

create_index_patterns() {
  info "Creating Kibana index patterns..."
  local patterns=("wazuh-alerts-*" "wazuh-archives-*" "logs-syslog-*" "logs-auth-*" "metrics-zabbix-*")
  for pattern in "${patterns[@]}"; do
    local id
    id=$(echo "${pattern}" | tr -d '*')
    curl -sf ${AUTH} -X POST "${KIBANA_URL}/api/saved_objects/index-pattern/${id}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "{\"attributes\":{\"title\":\"${pattern}\",\"timeFieldName\":\"@timestamp\"}}" \
      | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'  Created: {r.get(\"id\",\"?\")}')" 2>/dev/null || \
      warn "  Pattern ${pattern} may already exist."
  done
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Kibana Dashboard Import"
echo "  $(date)"
echo "============================================================"
echo ""

wait_for_kibana

echo ""
echo "── Step 1: Create Index Patterns ───────────────────────────"
create_index_patterns

echo ""
echo "── Step 2: Import Dashboards ───────────────────────────────"
for f in "${KIBANA_DIR}/dashboards"/*.json; do
  import_ndjson "${f}"
done

echo ""
echo "── Step 3: Import Saved Searches ───────────────────────────"
for f in "${KIBANA_DIR}/saved-searches"/*.json; do
  import_ndjson "${f}"
done

echo ""
echo "── Step 4: Import Visualizations ───────────────────────────"
for f in "${KIBANA_DIR}/visualizations"/*.json; do
  import_ndjson "${f}"
done

echo ""
info "Dashboard import complete."
info "Access Kibana at: ${KIBANA_URL}"
info "Navigate to: Dashboards → SOC Security Operations"
