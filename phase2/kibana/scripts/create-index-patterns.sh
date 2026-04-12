#!/usr/bin/env bash
# =============================================================================
# create-index-patterns.sh - Set up Kibana index patterns for Phase 2
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

KIBANA_HOST="${KIBANA_HOST:-localhost}"
KIBANA_PORT="${KIBANA_PORT:-5601}"
KIBANA_URL="http://${KIBANA_HOST}:${KIBANA_PORT}"
KIBANA_USER="${ELASTIC_USERNAME:-elastic}"
KIBANA_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${KIBANA_USER}:${KIBANA_PASS}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

create_pattern() {
  local pattern="$1"
  local id="${2:-${pattern}}"
  local default="${3:-false}"

  info "Creating index pattern: ${pattern}"
  local result
  result=$(curl -sf ${AUTH} -X POST "${KIBANA_URL}/api/saved_objects/index-pattern/${id}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"attributes\":{\"title\":\"${pattern}\",\"timeFieldName\":\"@timestamp\"}}" 2>&1)

  echo "${result}" | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
    if 'id' in r:
        print(f'  Created: {r[\"id\"]}')
    elif 'error' in r:
        print(f'  Warn: {r.get(\"message\", r.get(\"error\"))}')
    else:
        print(f'  Response: {r}')
except:
    print(f'  Raw: {sys.stdin.read()[:100]}')
" 2>/dev/null || warn "  Could not parse response for ${pattern}"

  if [[ "${default}" == "true" ]]; then
    curl -sf ${AUTH} -X POST "${KIBANA_URL}/api/kibana/settings" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "{\"changes\":{\"defaultIndex\":\"${id}\"}}" > /dev/null 2>&1 && \
      info "  Set as default index pattern." || warn "  Could not set as default."
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Kibana Index Pattern Setup"
echo "  $(date)"
echo "============================================================"
echo ""

# Security log patterns
create_pattern "wazuh-alerts-*"   "wazuh-alerts"   "true"
create_pattern "wazuh-archives-*" "wazuh-archives"  "false"
create_pattern "logs-auth-*"      "logs-auth"       "false"
create_pattern "logs-syslog-*"    "logs-syslog"     "false"

# Metrics pattern
create_pattern "metrics-zabbix-*" "metrics-zabbix"  "false"

# Combined pattern for unified view
create_pattern "wazuh-alerts-*,logs-auth-*,logs-syslog-*" "soc-all-logs" "false"

echo ""
info "Index pattern setup complete."
info "Verify at: ${KIBANA_URL}/app/management/kibana/indexPatterns"
