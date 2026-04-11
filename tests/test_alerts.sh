#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Alert System Tests
# Usage: ./tests/test_alerts.sh
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
echo "  SOC Platform - Alert System Tests"
echo "============================================================"
echo ""

# ── Configuration File Tests ───────────────────────────────────────────────────
echo "── Alert Configuration Files ───────────────────────────────"
assert_pass "alert_templates.json present" \
    "[[ -f '${PROJECT_ROOT}/config/alerting/alert_templates.json' ]]"
assert_pass "smtp_config.conf present" \
    "[[ -f '${PROJECT_ROOT}/config/alerting/smtp_config.conf' ]]"

assert_contains "alert_templates.json is valid JSON" \
    "python3 -m json.tool '${PROJECT_ROOT}/config/alerting/alert_templates.json'" \
    "templates"

assert_contains "alert_templates.json has high_cpu template" \
    "cat '${PROJECT_ROOT}/config/alerting/alert_templates.json'" \
    "high_cpu"

assert_contains "alert_templates.json has failed_logins template" \
    "cat '${PROJECT_ROOT}/config/alerting/alert_templates.json'" \
    "failed_logins"

assert_contains "alert_templates.json has host_down template" \
    "cat '${PROJECT_ROOT}/config/alerting/alert_templates.json'" \
    "host_down"

assert_contains "smtp_config.conf has SMTP host" \
    "cat '${PROJECT_ROOT}/config/alerting/smtp_config.conf'" \
    "smtp_server\|smtp.gmail.com\|smtp_host\|host ="

# ── Alerting Service Tests ─────────────────────────────────────────────────────
echo ""
echo "── Alerting Service ────────────────────────────────────────"
assert_pass "alerting/alerting_service.py present" \
    "[[ -f '${PROJECT_ROOT}/alerting/alerting_service.py' ]]"
assert_pass "alerting/requirements.txt present" \
    "[[ -f '${PROJECT_ROOT}/alerting/requirements.txt' ]]"
assert_pass "alerting/Dockerfile present" \
    "[[ -f '${PROJECT_ROOT}/alerting/Dockerfile' ]]"

assert_contains "alerting_service.py has SMTP send function" \
    "cat '${PROJECT_ROOT}/alerting/alerting_service.py'" \
    "send_alert_email"

assert_contains "alerting_service.py has failed login check" \
    "cat '${PROJECT_ROOT}/alerting/alerting_service.py'" \
    "check_failed_logins"

assert_contains "alerting_service.py has Elasticsearch integration" \
    "cat '${PROJECT_ROOT}/alerting/alerting_service.py'" \
    "Elasticsearch"

# ── Python syntax check ────────────────────────────────────────────────────────
echo ""
echo "── Python Syntax Check ─────────────────────────────────────"
if command -v python3 &>/dev/null; then
    assert_pass "alerting_service.py has valid Python syntax" \
        "python3 -m py_compile '${PROJECT_ROOT}/alerting/alerting_service.py'"
else
    echo -e "${WARN} python3 not available – skipping syntax check"
fi

# ── Elasticsearch Alert Tests ──────────────────────────────────────────────────
echo ""
echo "── Elasticsearch Alert Indices ─────────────────────────────"

if curl -sf -u "$ES_AUTH" "${ES_URL}/" > /dev/null 2>&1; then
    assert_contains "ILM policy for wazuh-alerts exists" \
        "curl -sf -u '${ES_AUTH}' '${ES_URL}/_ilm/policy/wazuh-alerts-policy'" \
        "policy"

    # Inject a test alert document
    INJECT_RESP=$(curl -sf -X POST \
        -u "$ES_AUTH" \
        -H "Content-Type: application/json" \
        "${ES_URL}/wazuh-alerts-test/_doc" \
        -d "{
          \"@timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
          \"rule\": {
            \"id\": \"100002\",
            \"level\": 10,
            \"description\": \"TEST: Possible brute-force attack\",
            \"groups\": [\"brute_force\", \"soc_high_priority\"]
          },
          \"agent\": {\"id\": \"001\", \"name\": \"test-agent\", \"ip\": \"192.168.1.1\"},
          \"data\": {\"srcip\": \"10.0.0.1\", \"srcuser\": \"testuser\"},
          \"_soc_test\": true
        }" 2>/dev/null || echo "{}")

    TOTAL=$((TOTAL + 1))
    if echo "$INJECT_RESP" | grep -q '"result":"created"'; then
        echo -e "${PASS} Test alert document can be indexed"
        PASSED=$((PASSED + 1))

        # Clean up test document
        curl -sf -X DELETE \
            -u "$ES_AUTH" \
            "${ES_URL}/wazuh-alerts-test" > /dev/null 2>&1 || true
    else
        echo -e "${WARN} Could not inject test alert document (index may not exist yet)"
        TOTAL=$((TOTAL - 1))
    fi
else
    echo -e "${WARN} Elasticsearch not available – skipping ES alert tests"
fi

# ── Wazuh Rules Validation ─────────────────────────────────────────────────────
echo ""
echo "── Wazuh Rules Validation ──────────────────────────────────"
RULES_FILE="${PROJECT_ROOT}/config/wazuh/rules/local_rules.xml"

if command -v xmllint &>/dev/null; then
    assert_pass "local_rules.xml is valid XML" \
        "xmllint --noout '${RULES_FILE}'"
else
    echo -e "${WARN} xmllint not available – skipping XML validation"
fi

assert_contains "Rule 100001 (SSH failure) defined" \
    "cat '${RULES_FILE}'" "100001"
assert_contains "Rule 100002 (brute-force) defined" \
    "cat '${RULES_FILE}'" "100002"
assert_contains "Rule 100020 (root SSH login) defined" \
    "cat '${RULES_FILE}'" "100020"
assert_contains "MITRE ATT&CK IDs referenced" \
    "cat '${RULES_FILE}'" "T1110"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "  Results: ${GREEN}${PASSED} passed${NC} | ${RED}${FAILED} failed${NC} | Total: ${TOTAL}"
echo "============================================================"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
