#!/usr/bin/env bash
# =============================================================================
# init-indices.sh - Create initial Elasticsearch indices for Phase 2
# SOC Platform - Data Analytics Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"

TEMPLATES_DIR="${PHASE2_DIR}/elasticsearch/index-templates"
ILM_DIR="${PHASE2_DIR}/elasticsearch/ilm-policies"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

wait_for_es() {
  info "Waiting for Elasticsearch at ${ES_URL} ..."
  for i in $(seq 1 30); do
    if curl -sf ${AUTH} "${ES_URL}/_cluster/health" > /dev/null 2>&1; then
      info "Elasticsearch is ready."
      return 0
    fi
    echo -n "."
    sleep 5
  done
  error "Elasticsearch did not become ready within 150 seconds."
  exit 1
}

apply_ilm_policy() {
  local name="$1"
  local file="$2"
  info "Applying ILM policy: ${name}"
  curl -sf ${AUTH} -X PUT "${ES_URL}/_ilm/policy/${name}" \
    -H "Content-Type: application/json" \
    -d "@${file}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  OK' if r.get('acknowledged') else '  WARN: '+str(r))"
}

apply_template() {
  local name="$1"
  local file="$2"
  info "Applying index template: ${name}"
  curl -sf ${AUTH} -X PUT "${ES_URL}/_index_template/${name}" \
    -H "Content-Type: application/json" \
    -d "@${file}" | python3 -c "import sys,json; r=json.load(sys.stdin); print('  OK' if r.get('acknowledged') else '  WARN: '+str(r))"
}

bootstrap_index() {
  local alias="$1"
  local index="${alias}-000001"
  info "Bootstrapping write index: ${index} (alias: ${alias})"
  if curl -sf ${AUTH} "${ES_URL}/${index}" > /dev/null 2>&1; then
    warn "  Index ${index} already exists, skipping."
    return 0
  fi
  curl -sf ${AUTH} -X PUT "${ES_URL}/${index}" \
    -H "Content-Type: application/json" \
    -d "{\"aliases\": {\"${alias}\": {\"is_write_index\": true}}}" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('  OK' if r.get('acknowledged') else '  WARN: '+str(r))"
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Elasticsearch Index Initialization"
echo "  $(date)"
echo "============================================================"
echo ""

wait_for_es

echo ""
echo "── Step 1: Apply ILM Policies ──────────────────────────────"
apply_ilm_policy "wazuh-ilm-policy"   "${ILM_DIR}/wazuh-ilm-policy.json"
apply_ilm_policy "logs-ilm-policy"    "${ILM_DIR}/logs-ilm-policy.json"
apply_ilm_policy "metrics-ilm-policy" "${ILM_DIR}/metrics-ilm-policy.json"

echo ""
echo "── Step 2: Apply Index Templates ───────────────────────────"
apply_template "wazuh-alerts"    "${TEMPLATES_DIR}/wazuh-alerts-template.json"
apply_template "wazuh-archives"  "${TEMPLATES_DIR}/wazuh-archives-template.json"
apply_template "logs-syslog"     "${TEMPLATES_DIR}/logs-syslog-template.json"
apply_template "logs-auth"       "${TEMPLATES_DIR}/logs-auth-template.json"
apply_template "metrics-zabbix"  "${TEMPLATES_DIR}/metrics-zabbix-template.json"

echo ""
echo "── Step 3: Bootstrap Write Indices ─────────────────────────"
bootstrap_index "wazuh-alerts"
bootstrap_index "wazuh-archives"
bootstrap_index "logs-syslog"
bootstrap_index "logs-auth"
bootstrap_index "metrics-zabbix"

echo ""
info "Elasticsearch index initialization complete."
echo ""

# Verify
info "Cluster state:"
curl -sf ${AUTH} "${ES_URL}/_cat/indices?v&h=index,health,status,pri,rep,docs.count,store.size" || true
echo ""
