#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Zabbix API Tests
# Usage: ./tests/test_zabbix_api.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"

TOTAL=0
PASSED=0
FAILED=0

ZABBIX_URL="${ZABBIX_URL:-http://localhost:8080}"
ZABBIX_USER="${ZABBIX_USER:-Admin}"
ZABBIX_PASS="${ZABBIX_PASS:-zabbix}"

assert_pass() {
    local desc="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${PASS} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${FAIL} ${desc}"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    TOTAL=$((TOTAL + 1))
    local output
    output=$(eval "$cmd" 2>/dev/null || echo "")
    if echo "$output" | grep -q "$expected"; then
        echo -e "${PASS} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${FAIL} ${desc} (expected to contain: '$expected')"
        FAILED=$((FAILED + 1))
    fi
}

echo ""
echo "============================================================"
echo "  SOC Platform - Zabbix API Tests"
echo "  URL: ${ZABBIX_URL}"
echo "============================================================"
echo ""

# ── Connectivity ───────────────────────────────────────────────────────────────
echo "── Connectivity Tests ──────────────────────────────────────"
assert_pass "Zabbix web reachable" "curl -sf '${ZABBIX_URL}/'"
assert_pass "Zabbix API endpoint reachable" "curl -sf '${ZABBIX_URL}/api_jsonrpc.php'"
assert_pass "Zabbix server port 10051 open" "nc -z localhost 10051"
assert_pass "Zabbix agent port 10050 open" "nc -z localhost 10050"

# ── Authentication ─────────────────────────────────────────────────────────────
echo ""
echo "── Authentication Tests ────────────────────────────────────"

TOKEN_RESP=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"${ZABBIX_USER}\",\"password\":\"${ZABBIX_PASS}\"},\"id\":1}" \
    "${ZABBIX_URL}/api_jsonrpc.php" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

TOTAL=$((TOTAL + 1))
if [[ -n "$AUTH_TOKEN" ]]; then
    echo -e "${PASS} Zabbix API authentication successful"
    PASSED=$((PASSED + 1))
else
    echo -e "${FAIL} Zabbix API authentication failed"
    FAILED=$((FAILED + 1))
fi

if [[ -z "$AUTH_TOKEN" ]]; then
    echo -e "${WARN} Skipping API tests (no auth token)"
    echo ""
    echo "Results: ${PASSED}/${TOTAL} passed"
    exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
fi

# ── API Feature Tests ──────────────────────────────────────────────────────────
echo ""
echo "── API Feature Tests ───────────────────────────────────────"

# Get API version
assert_contains "Zabbix API version returned" \
    "curl -sf -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"apiinfo.version\",\"id\":1}' '${ZABBIX_URL}/api_jsonrpc.php'" \
    "\"result\""

# List host groups
assert_contains "Host groups retrievable" \
    "curl -sf -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.get\",\"params\":{\"output\":\"extend\"},\"auth\":\"${AUTH_TOKEN}\",\"id\":2}' '${ZABBIX_URL}/api_jsonrpc.php'" \
    "\"result\""

# List hosts
assert_contains "Hosts retrievable" \
    "curl -sf -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"host.get\",\"params\":{\"output\":\"extend\"},\"auth\":\"${AUTH_TOKEN}\",\"id\":3}' '${ZABBIX_URL}/api_jsonrpc.php'" \
    "\"result\""

# List triggers
assert_contains "Triggers retrievable" \
    "curl -sf -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"trigger.get\",\"params\":{\"output\":\"extend\",\"limit\":5},\"auth\":\"${AUTH_TOKEN}\",\"id\":4}' '${ZABBIX_URL}/api_jsonrpc.php'" \
    "\"result\""

# List media types
assert_contains "Media types retrievable" \
    "curl -sf -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"mediatype.get\",\"params\":{\"output\":\"extend\"},\"auth\":\"${AUTH_TOKEN}\",\"id\":5}' '${ZABBIX_URL}/api_jsonrpc.php'" \
    "\"result\""

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "  Results: ${GREEN}${PASSED} passed${NC} | ${RED}${FAILED} failed${NC} | Total: ${TOTAL}"
echo "============================================================"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
