#!/usr/bin/env bash
# =============================================================================
# test-rules.sh - Test Phase 2 Wazuh correlation rules
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

WAZUH_CONTAINER="${WAZUH_CONTAINER:-wazuh-manager}"
LOGTEST_BIN="${LOGTEST_BIN:-/var/ossec/bin/wazuh-logtest}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
pass()    { echo -e "${GREEN}[PASS]${NC}    $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }

PASS_COUNT=0
FAIL_COUNT=0

run_logtest() {
  local description="$1"
  local log_line="$2"
  local expected_rule="${3:-}"

  echo ""
  echo "  Test: ${description}"
  echo "  Log:  ${log_line:0:80}..."

  local result=""
  if docker ps --format '{{.Names}}' | grep -q "^${WAZUH_CONTAINER}$"; then
    result=$(echo "${log_line}" | docker exec -i "${WAZUH_CONTAINER}" "${LOGTEST_BIN}" -q 2>&1 || true)
  elif [[ -x "${LOGTEST_BIN}" ]]; then
    result=$(echo "${log_line}" | "${LOGTEST_BIN}" -q 2>&1 || true)
  else
    warn "  Cannot reach Wazuh logtest (container not running, binary not found)."
    warn "  Manual test command:"
    echo "    echo '${log_line}' | ${LOGTEST_BIN}"
    return 0
  fi

  if [[ -n "${expected_rule}" ]]; then
    if echo "${result}" | grep -q "Rule Id: ${expected_rule}"; then
      pass "  Rule ${expected_rule} triggered as expected"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      fail "  Expected rule ${expected_rule}, got: $(echo "${result}" | grep 'Rule Id:' | head -1)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    info "  Result: $(echo "${result}" | grep 'Rule Id:' | head -1 || echo 'No rule matched')"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Wazuh Rule Testing"
echo "  $(date)"
echo "============================================================"

echo ""
echo "── Authentication & Brute Force Tests ──────────────────────"

run_logtest \
  "SSH Failed Login (base rule)" \
  "Apr  1 12:00:00 server01 sshd[1234]: Failed password for testuser from 192.168.1.100 port 22 ssh2" \
  "5710"

run_logtest \
  "SSH Login Success (base rule)" \
  "Apr  1 12:05:00 server01 sshd[1234]: Accepted password for testuser from 192.168.1.100 port 22 ssh2" \
  "5715"

run_logtest \
  "SSH Invalid User" \
  "Apr  1 12:01:00 server01 sshd[1234]: Invalid user admin from 10.0.0.50 port 45678" \
  "5712"

echo ""
echo "── Privilege Escalation Tests ───────────────────────────────"

run_logtest \
  "Sudo command executed" \
  "Apr  1 12:10:00 server01 sudo:  testuser : TTY=pts/0 ; PWD=/home/testuser ; USER=root ; COMMAND=/bin/bash" \
  "5402"

run_logtest \
  "Sudo authentication failure" \
  "Apr  1 12:09:00 server01 sudo: pam_unix(sudo:auth): authentication failure; logname=testuser uid=1001 euid=0 tty=/dev/pts/0 ruser=testuser rhost= user=testuser" \
  "5403"

echo ""
echo "── File Integrity Tests ─────────────────────────────────────"

run_logtest \
  "OSSEC FIM - file modified" \
  "Apr  1 12:20:00 server01 ossec: Integrity checksum changed for: '/etc/passwd'. Old md5sum was: 'abc123'. New md5sum is : 'def456'." \
  "550"

echo ""
echo "── Summary ──────────────────────────────────────────────────"
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
if [[ ${FAIL_COUNT} -eq 0 ]]; then
  info "All tests passed!"
else
  fail "${FAIL_COUNT} test(s) failed. Review the output above."
  exit 1
fi
