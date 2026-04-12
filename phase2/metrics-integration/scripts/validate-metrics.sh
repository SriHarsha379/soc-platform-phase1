#!/usr/bin/env bash
# =============================================================================
# validate-metrics.sh - Validate Zabbix → Elasticsearch metrics ingestion
# SOC Platform Phase 2 - Metrics Integration
# =============================================================================
set -euo pipefail

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"
INDEX="${METRICS_INDEX:-metrics-zabbix-*}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
pass()  { echo -e "${GREEN}[PASS]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

PASS_COUNT=0
FAIL_COUNT=0

check() {
  local desc="$1"; local cmd="$2"
  if eval "${cmd}" > /dev/null 2>&1; then
    pass "${desc}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    fail "${desc}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Metrics Validation"
echo "  $(date)"
echo "============================================================"
echo ""

# ES connectivity
check "Elasticsearch reachable" \
  "curl -sf ${AUTH} '${ES_URL}/_cluster/health'"

# Index template exists
check "metrics-zabbix index template exists" \
  "curl -sf ${AUTH} '${ES_URL}/_index_template/metrics-zabbix' | python3 -c \"import sys,json; t=json.load(sys.stdin); sys.exit(0 if t.get('index_templates') else 1)\""

# ILM policy exists
check "metrics-ilm-policy exists" \
  "curl -sf ${AUTH} '${ES_URL}/_ilm/policy/metrics-ilm-policy' | python3 -c \"import sys,json; p=json.load(sys.stdin); sys.exit(0 if p else 1)\""

# Data in metrics index (last 5 min)
info "Checking for recent metrics data..."
RECENT=$(curl -sf ${AUTH} -X GET "${ES_URL}/${INDEX}/_count" \
  -H "Content-Type: application/json" \
  -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' \
  2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")

if [[ "${RECENT}" -gt 0 ]]; then
  pass "Recent metrics data present: ${RECENT} documents in last 5 minutes"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  warn "No metrics data in last 5 minutes. Is the exporter running?"
  warn "  Check: systemctl status soc-metrics-exporter"
  warn "  Or run: python3 zabbix_to_es_exporter.py --config config.yaml --once"
fi

# Field validation (check key ECS fields exist in latest doc)
info "Checking document field structure..."
LATEST=$(curl -sf ${AUTH} -X GET "${ES_URL}/${INDEX}/_search" \
  -H "Content-Type: application/json" \
  -d '{"size":1,"sort":[{"@timestamp":{"order":"desc"}}]}' 2>/dev/null || echo "{}")

echo "${LATEST}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
hits = data.get('hits', {}).get('hits', [])
if not hits:
    print('  WARN: No documents found in metrics index')
    sys.exit(0)
doc = hits[0].get('_source', {})
required_fields = ['@timestamp', 'host', 'metric', 'zabbix']
for field in required_fields:
    if field in doc:
        print(f'  \033[0;32m[PASS]\033[0m  Field present: {field}')
    else:
        print(f'  \033[0;31m[FAIL]\033[0m  Missing field: {field}')
print(f'  Latest document @timestamp: {doc.get(\"@timestamp\", \"N/A\")}')
print(f'  Host: {doc.get(\"host\", {}).get(\"name\", \"N/A\")}')
print(f'  Metric: {doc.get(\"metric\", {}).get(\"name\", \"N/A\")} = {doc.get(\"metric\", {}).get(\"value\", \"N/A\")}')
" 2>/dev/null || warn "Could not parse latest document."

echo ""
echo "── Summary ──────────────────────────────────────────────────"
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  info "Metrics pipeline validation passed!"
else
  fail "${FAIL_COUNT} check(s) failed. Review the output above."
  exit 1
fi
