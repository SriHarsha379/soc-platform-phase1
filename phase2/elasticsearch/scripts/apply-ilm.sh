#!/usr/bin/env bash
# =============================================================================
# apply-ilm.sh - Apply / update ILM policies for Phase 2
# SOC Platform - Data Analytics Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ILM_DIR="$(cd "${SCRIPT_DIR}/../ilm-policies" && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

apply_policy() {
  local name="$1"
  local file="${ILM_DIR}/${name}.json"
  if [[ ! -f "${file}" ]]; then
    error "Policy file not found: ${file}"
    return 1
  fi
  info "Applying ILM policy: ${name}"
  local response
  response=$(curl -sf ${AUTH} -X PUT "${ES_URL}/_ilm/policy/${name}" \
    -H "Content-Type: application/json" \
    -d "@${file}")
  if echo "${response}" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('acknowledged') else 1)" 2>/dev/null; then
    info "  ✓ ${name} applied successfully"
  else
    warn "  ⚠ Response: ${response}"
  fi
}

verify_policies() {
  echo ""
  info "Verifying ILM policies:"
  curl -sf ${AUTH} "${ES_URL}/_ilm/policy?filter_path=*.name,*.policy.phases" \
    | python3 -c "
import sys, json
policies = json.load(sys.stdin)
for name, policy in policies.items():
    phases = list(policy.get('policy', {}).get('phases', {}).keys())
    print(f'  {name}: phases={phases}')
" || curl -sf ${AUTH} "${ES_URL}/_ilm/policy" | python3 -m json.tool || true
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - ILM Policy Application"
echo "  $(date)"
echo "============================================================"
echo ""

apply_policy "wazuh-ilm-policy"
apply_policy "logs-ilm-policy"
apply_policy "metrics-ilm-policy"

verify_policies

echo ""
info "ILM policy application complete."
