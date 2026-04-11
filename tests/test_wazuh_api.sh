#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Wazuh API Tests
# Usage: ./tests/test_wazuh_api.sh
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

WAZUH_URL="${WAZUH_URL:-https://localhost:55000}"
WAZUH_USER="${WAZUH_API_USER:-wazuh-wui}"
WAZUH_PASS="${WAZUH_API_PASSWORD:-wazuh_api_secure_password}"
ES_URL="${ES_URL:-http://localhost:9200}"
ES_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"

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
        echo -e "${FAIL} ${desc} (expected: '${expected}')"
        FAILED=$((FAILED + 1))
    fi
}

echo ""
echo "============================================================"
echo "  SOC Platform - Wazuh API Tests"
echo "  URL: ${WAZUH_URL}"
echo "============================================================"
echo ""

# ── Connectivity ───────────────────────────────────────────────────────────────
echo "── Connectivity Tests ──────────────────────────────────────"
assert_pass "Wazuh Manager API port 55000 open" "nc -z localhost 55000"
assert_pass "Wazuh Manager API reachable (HTTPS)" "curl -ksfL '${WAZUH_URL}/'"
assert_pass "Wazuh agent enrollment port 1515 open" "nc -z localhost 1515"

# ── Authentication ─────────────────────────────────────────────────────────────
echo ""
echo "── Authentication Tests ────────────────────────────────────"

TOKEN_RESP=$(curl -ksf -X POST \
    -H "Content-Type: application/json" \
    -u "${WAZUH_USER}:${WAZUH_PASS}" \
    "${WAZUH_URL}/security/user/authenticate" 2>/dev/null || echo "{}")

WAZUH_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4 || echo "")

TOTAL=$((TOTAL + 1))
if [[ -n "$WAZUH_TOKEN" ]]; then
    echo -e "${PASS} Wazuh API authentication successful"
    PASSED=$((PASSED + 1))
else
    echo -e "${WARN} Wazuh API authentication failed (may still be initializing)"
    FAILED=$((FAILED + 1))
fi

# ── API Feature Tests ──────────────────────────────────────────────────────────
if [[ -n "$WAZUH_TOKEN" ]]; then
    echo ""
    echo "── API Feature Tests ───────────────────────────────────────"

    assert_contains "Wazuh manager info retrievable" \
        "curl -ksf -H 'Authorization: Bearer ${WAZUH_TOKEN}' '${WAZUH_URL}/manager/info'" \
        "\"data\""

    assert_contains "Wazuh manager status retrievable" \
        "curl -ksf -H 'Authorization: Bearer ${WAZUH_TOKEN}' '${WAZUH_URL}/manager/status'" \
        "\"data\""

    assert_contains "Wazuh agents list retrievable" \
        "curl -ksf -H 'Authorization: Bearer ${WAZUH_TOKEN}' '${WAZUH_URL}/agents'" \
        "\"data\""

    assert_contains "Wazuh rules list retrievable" \
        "curl -ksf -H 'Authorization: Bearer ${WAZUH_TOKEN}' '${WAZUH_URL}/rules'" \
        "\"data\""

    assert_contains "Wazuh decoders list retrievable" \
        "curl -ksf -H 'Authorization: Bearer ${WAZUH_TOKEN}' '${WAZUH_URL}/decoders'" \
        "\"data\""
fi

# ── Elasticsearch Integration ──────────────────────────────────────────────────
echo ""
echo "── Elasticsearch Integration Tests ────────────────────────"
assert_pass "Elasticsearch reachable" "curl -sf -u '${ES_AUTH}' '${ES_URL}/'"
assert_contains "Elasticsearch cluster healthy" \
    "curl -sf -u '${ES_AUTH}' '${ES_URL}/_cluster/health'" \
    "\"status\""
assert_contains "Wazuh index template exists" \
    "curl -sf -u '${ES_AUTH}' '${ES_URL}/_index_template/wazuh-alerts'" \
    "wazuh"

# ── Configuration File Tests ───────────────────────────────────────────────────
echo ""
echo "── Configuration File Tests ────────────────────────────────"
assert_pass "ossec.conf present" "[[ -f '${PROJECT_ROOT}/config/wazuh/ossec.conf' ]]"
assert_pass "local_rules.xml present" "[[ -f '${PROJECT_ROOT}/config/wazuh/rules/local_rules.xml' ]]"
assert_pass "local_decoders.xml present" "[[ -f '${PROJECT_ROOT}/config/wazuh/rules/decoders/local.xml' ]]"
assert_pass "agent.conf present" "[[ -f '${PROJECT_ROOT}/config/wazuh/agent_configs/agent.conf' ]]"

assert_contains "ossec.conf has log collection config" \
    "cat '${PROJECT_ROOT}/config/wazuh/ossec.conf'" \
    "localfile"

assert_contains "local_rules.xml has brute-force rule" \
    "cat '${PROJECT_ROOT}/config/wazuh/rules/local_rules.xml'" \
    "brute_force"

assert_contains "local_rules.xml has failed login rule" \
    "cat '${PROJECT_ROOT}/config/wazuh/rules/local_rules.xml'" \
    "authentication_failure"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "  Results: ${GREEN}${PASSED} passed${NC} | ${RED}${FAILED} failed${NC} | Total: ${TOTAL}"
echo "============================================================"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
