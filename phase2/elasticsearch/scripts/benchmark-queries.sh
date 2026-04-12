#!/usr/bin/env bash
# =============================================================================
# benchmark-queries.sh - Performance benchmark for Phase 2 ES queries
# SOC Platform - Data Analytics Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERIES_DIR="$(cd "${SCRIPT_DIR}/../queries" && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"
RUNS="${BENCHMARK_RUNS:-5}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

run_benchmark() {
  local name="$1"
  local index="${2:-wazuh-alerts-*}"
  local query_file="${QUERIES_DIR}/${name}.json"

  if [[ ! -f "${query_file}" ]]; then
    warn "Query file not found: ${query_file}, using simple match_all"
    query='{"size":0,"query":{"match_all":{}}}'
  else
    # Extract just the "query" block for the search API
    query=$(python3 -c "
import json, sys
with open('${query_file}') as f:
    data = json.load(f)
search = {}
if 'query' in data:
    search = data['query']
elif 'size' in data:
    search = data
else:
    search = {'size': 0, 'query': {'match_all': {}}}
print(json.dumps(search))
")
  fi

  echo ""
  echo -e "${CYAN}── Benchmark: ${name} (index: ${index}) ──${NC}"
  local total_ms=0
  local min_ms=999999
  local max_ms=0

  for i in $(seq 1 "${RUNS}"); do
    local start_ns
    start_ns=$(date +%s%N)
    response=$(curl -sf ${AUTH} -X GET "${ES_URL}/${index}/_search" \
      -H "Content-Type: application/json" \
      -d "${query}" 2>&1)
    local end_ns
    end_ns=$(date +%s%N)
    local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

    local took
    took=$(echo "${response}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('took','N/A'))" 2>/dev/null || echo "N/A")
    echo "  Run ${i}: wall=${elapsed_ms}ms  ES.took=${took}ms"

    total_ms=$((total_ms + elapsed_ms))
    [[ ${elapsed_ms} -lt ${min_ms} ]] && min_ms=${elapsed_ms}
    [[ ${elapsed_ms} -gt ${max_ms} ]] && max_ms=${elapsed_ms}
  done

  local avg_ms=$((total_ms / RUNS))
  echo "  ─────────────────────────────"
  echo "  Min: ${min_ms}ms | Max: ${max_ms}ms | Avg: ${avg_ms}ms"
  if [[ ${avg_ms} -lt 5000 ]]; then
    echo -e "  Status: ${GREEN}PASS (< 5s target)${NC}"
  else
    echo -e "  Status: ${RED}FAIL (> 5s target)${NC}"
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Query Performance Benchmark"
echo "  $(date)"
echo "  Runs per query: ${RUNS}"
echo "============================================================"

# Simple cluster health check
info "Cluster health:"
curl -sf ${AUTH} "${ES_URL}/_cluster/health?pretty" | python3 -c "
import sys, json
h = json.load(sys.stdin)
print(f\"  Status: {h['status']} | Nodes: {h['number_of_nodes']} | Shards: {h['active_shards']}\")" || warn "Could not reach Elasticsearch"

run_benchmark "brute-force-detection"   "wazuh-alerts-*,logs-auth-*"
run_benchmark "privilege-escalation"    "wazuh-alerts-*,logs-auth-*"
run_benchmark "data-exfiltration"       "wazuh-alerts-*"
run_benchmark "impossible-travel"       "logs-auth-*"
run_benchmark "time-based-anomalies"    "wazuh-alerts-*,logs-auth-*"

echo ""
info "Benchmark complete. Target: all queries < 5 seconds average."
echo ""
