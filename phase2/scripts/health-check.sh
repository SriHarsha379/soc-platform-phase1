#!/usr/bin/env bash
# =============================================================================
# health-check.sh - Phase 2 System Health Verification
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
KIBANA_HOST="${KIBANA_HOST:-localhost}"
KIBANA_PORT="${KIBANA_PORT:-5601}"
KIBANA_URL="http://${KIBANA_HOST}:${KIBANA_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"
WAZUH_CONTAINER="${WAZUH_CONTAINER:-wazuh-manager}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}[PASS]${NC}  $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { echo -e "  ${RED}[FAIL]${NC}  $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info()  { echo -e "         $*"; }

PASS_COUNT=0
FAIL_COUNT=0

check() {
  local desc="$1"; local cmd="$2"
  if eval "${cmd}" > /dev/null 2>&1; then
    pass "${desc}"
  else
    fail "${desc}"
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Health Check"
echo "  $(date)"
echo "============================================================"

# ── Elasticsearch ─────────────────────────────────────────────────────────────
echo ""
echo "── Elasticsearch ────────────────────────────────────────────"

check "ES reachable" \
  "curl -sf ${AUTH} '${ES_URL}/_cluster/health'"

ES_STATUS=$(curl -sf ${AUTH} "${ES_URL}/_cluster/health" 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unreachable")

case "${ES_STATUS}" in
  green)  pass "ES cluster status: green" ;;
  yellow) warn "ES cluster status: yellow (replicas unassigned - OK for single node)" ;;
  red)    fail "ES cluster status: red (data unavailable!)" ;;
  *)      fail "ES cluster status: ${ES_STATUS}" ;;
esac

check "ILM policy: wazuh-ilm-policy exists" \
  "curl -sf ${AUTH} '${ES_URL}/_ilm/policy/wazuh-ilm-policy'"
check "ILM policy: logs-ilm-policy exists" \
  "curl -sf ${AUTH} '${ES_URL}/_ilm/policy/logs-ilm-policy'"
check "ILM policy: metrics-ilm-policy exists" \
  "curl -sf ${AUTH} '${ES_URL}/_ilm/policy/metrics-ilm-policy'"

check "Index template: wazuh-alerts exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/wazuh-alerts'"
check "Index template: wazuh-archives exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/wazuh-archives'"
check "Index template: logs-syslog exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/logs-syslog'"
check "Index template: logs-auth exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/logs-auth'"
check "Index template: metrics-zabbix exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/metrics-zabbix'"

check "Write index: wazuh-alerts-000001 exists" \
  "curl -sf ${AUTH} '${ES_URL}/wazuh-alerts-000001'"

# ── Data Presence ─────────────────────────────────────────────────────────────
echo ""
echo "── Data Presence ────────────────────────────────────────────"

for pattern in "wazuh-alerts-*" "wazuh-archives-*" "metrics-zabbix-*"; do
  COUNT=$(curl -sf ${AUTH} "${ES_URL}/${pattern}/_count" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
  if [[ "${COUNT}" -gt 0 ]]; then
    pass "${pattern}: ${COUNT} documents"
  else
    warn "${pattern}: 0 documents (index may be empty - normal before ingestion)"
  fi
done

# ── Kibana ────────────────────────────────────────────────────────────────────
echo ""
echo "── Kibana ────────────────────────────────────────────────────"

check "Kibana reachable" \
  "curl -sf ${AUTH} '${KIBANA_URL}/api/status'"

KB_STATUS=$(curl -sf ${AUTH} "${KIBANA_URL}/api/status" 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('overall',{}).get('level','unknown'))" 2>/dev/null || echo "unreachable")
[[ "${KB_STATUS}" == "available" ]] && pass "Kibana status: available" || warn "Kibana status: ${KB_STATUS}"

# ── Wazuh ─────────────────────────────────────────────────────────────────────
echo ""
echo "── Wazuh ─────────────────────────────────────────────────────"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${WAZUH_CONTAINER}$"; then
  pass "Wazuh container running: ${WAZUH_CONTAINER}"

  # Check rules deployed
  RULES_COUNT=$(docker exec "${WAZUH_CONTAINER}" ls /var/ossec/etc/rules/*.xml 2>/dev/null | wc -l || echo "0")
  [[ "${RULES_COUNT}" -gt 0 ]] && pass "Wazuh custom rules deployed: ${RULES_COUNT} file(s)" || warn "No custom rules found in /var/ossec/etc/rules/"
else
  warn "Wazuh container '${WAZUH_CONTAINER}' not running - skipping Wazuh checks"
fi

# ── Metrics Exporter ──────────────────────────────────────────────────────────
echo ""
echo "── Metrics Exporter ──────────────────────────────────────────"

if systemctl is-active --quiet soc-metrics-exporter 2>/dev/null; then
  pass "soc-metrics-exporter service: active"
else
  warn "soc-metrics-exporter service: not running (may need manual start)"
  info "Start with: systemctl start soc-metrics-exporter"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "── Summary ───────────────────────────────────────────────────"
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
echo ""
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  echo -e "  ${GREEN}Phase 2 health check passed!${NC}"
else
  echo -e "  ${YELLOW}${FAIL_COUNT} check(s) failed. Review output above.${NC}"
fi
echo ""
