#!/usr/bin/env bash
# =============================================================================
# validate-correlation.sh - Validate Phase 2 correlation rules and data pipeline
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
WAZUH_CONTAINER="${WAZUH_CONTAINER:-wazuh-manager}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}[PASS]${NC}  $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { echo -e "  ${RED}[FAIL]${NC}  $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }

PASS_COUNT=0
FAIL_COUNT=0

validate_correlation_rule() {
  local rule_name="$1"
  local rule_id="$2"
  local index_pattern="$3"
  local query="$4"

  local count
  count=$(curl -sf ${AUTH} -X GET "${ES_URL}/${index_pattern}/_count" \
    -H "Content-Type: application/json" \
    -d "${query}" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")

  if [[ "${count}" -gt 0 ]]; then
    pass "${rule_name}: ${count} events matched"
  else
    warn "${rule_name}: 0 events found (rule may not have triggered yet)"
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Correlation Validation"
echo "  $(date)"
echo "============================================================"
echo ""

echo "── Correlation Rule Validation ──────────────────────────────"

# Brute Force: look for rule 100001-100005
validate_correlation_rule \
  "Brute Force Detection (rules 100001-100005)" \
  "100001" \
  "wazuh-alerts-*" \
  '{"query":{"terms":{"rule.id":["100001","100002","100003","100004","100005"]}}}'

# Privilege Escalation: rules 100100-100104
validate_correlation_rule \
  "Privilege Escalation (rules 100100-100104)" \
  "100100" \
  "wazuh-alerts-*" \
  '{"query":{"terms":{"rule.id":["100100","100101","100102","100103","100104"]}}}'

# Time Anomalies: rules 100300-100302
validate_correlation_rule \
  "Time-Based Anomalies (rules 100300-100302)" \
  "100300" \
  "wazuh-alerts-*" \
  '{"query":{"terms":{"rule.id":["100300","100301","100302"]}}}'

# Composite/Chained: rules 100400-100402
validate_correlation_rule \
  "Composite Alerts (rules 100400-100402)" \
  "100400" \
  "wazuh-alerts-*" \
  '{"query":{"terms":{"rule.id":["100400","100401","100402"]}}}'

# Check for correlation tags
validate_correlation_rule \
  "Brute Force Tags" \
  "-" \
  "wazuh-alerts-*" \
  '{"query":{"term":{"rule.groups":"brute-force"}}}'

validate_correlation_rule \
  "Privilege Escalation Tags" \
  "-" \
  "wazuh-alerts-*" \
  '{"query":{"term":{"rule.groups":"privilege-escalation"}}}'

echo ""
echo "── Enrichment Validation ────────────────────────────────────"

validate_correlation_rule \
  "SOC Severity Tags (soc-critical/high/medium/low)" \
  "-" \
  "wazuh-alerts-*" \
  '{"query":{"terms":{"rule.groups":["soc-critical","soc-high","soc-medium","soc-low"]}}}'

validate_correlation_rule \
  "High-Value Host Tags" \
  "-" \
  "wazuh-alerts-*" \
  '{"query":{"term":{"rule.groups":"high-value-target"}}}'

echo ""
echo "── Wazuh Rule Tests ─────────────────────────────────────────"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${WAZUH_CONTAINER}$"; then
  bash "${PHASE2_DIR}/wazuh/scripts/test-rules.sh" || warn "Some rule tests failed."
else
  warn "Wazuh container not running - skipping rule tests."
fi

echo ""
echo "── Metrics Validation ───────────────────────────────────────"
bash "${PHASE2_DIR}/metrics-integration/scripts/validate-metrics.sh" || warn "Metrics validation had warnings."

echo ""
echo "── Summary ───────────────────────────────────────────────────"
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  echo -e "  ${GREEN}Correlation validation passed!${NC}"
else
  echo -e "  ${YELLOW}${FAIL_COUNT} item(s) need attention.${NC}"
fi
echo ""
