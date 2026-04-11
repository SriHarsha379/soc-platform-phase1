#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Health Check Script
# Usage: ./scripts/health-check.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

TOTAL=0
PASSED=0
FAILED=0

check() {
    local name="$1"
    local cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${PASS} ${name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${FAIL} ${name}"
        FAILED=$((FAILED + 1))
    fi
}

cd "$PROJECT_ROOT"

if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

ES_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"
KIBANA_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"

echo ""
echo "============================================================"
echo "  SOC Platform Phase 1 - Health Check"
echo "  $(date)"
echo "============================================================"
echo ""

# ── Docker service checks ──────────────────────────────────────────────────────
echo -e "${INFO} Docker Service Status"
echo "─────────────────────────────────────"
check "zabbix-db container running"      "docker-compose ps zabbix-db | grep -q 'Up'"
check "zabbix-server container running"  "docker-compose ps zabbix-server | grep -q 'Up'"
check "zabbix-web container running"     "docker-compose ps zabbix-web | grep -q 'Up'"
check "zabbix-agent container running"   "docker-compose ps zabbix-agent | grep -q 'Up'"
check "elasticsearch container running"  "docker-compose ps elasticsearch | grep -q 'Up'"
check "kibana container running"         "docker-compose ps kibana | grep -q 'Up'"
check "wazuh-manager container running"  "docker-compose ps wazuh-manager | grep -q 'Up'"
check "soc-alerting container running"   "docker-compose ps soc-alerting | grep -q 'Up'"

echo ""
echo -e "${INFO} Service Connectivity"
echo "─────────────────────────────────────"
check "Elasticsearch HTTP (9200)"       "curl -sf -u '${ES_AUTH}' http://localhost:9200/"
check "Elasticsearch cluster health"    "curl -sf -u '${ES_AUTH}' http://localhost:9200/_cluster/health | grep -qv '\"status\":\"red\"'"
check "Kibana HTTP (5601)"              "curl -sf http://localhost:5601/api/status"
check "Zabbix Web (8080)"              "curl -sf http://localhost:8080/"
check "Zabbix Server (10051)"          "nc -z localhost 10051"
check "Zabbix Agent (10050)"           "nc -z localhost 10050"
check "Wazuh Manager API (55000)"      "curl -ksfL https://localhost:55000/ | grep -q 'Wazuh'"
check "Wazuh Agent port (1515)"        "nc -z localhost 1515"

echo ""
echo -e "${INFO} Elasticsearch Indices"
echo "─────────────────────────────────────"
check "Wazuh alerts index exists"       "curl -sf -u '${ES_AUTH}' http://localhost:9200/wazuh-alerts-* | grep -qv 'index_not_found'"
check "ILM policy exists"               "curl -sf -u '${ES_AUTH}' http://localhost:9200/_ilm/policy/wazuh-alerts-policy | grep -q 'policy'"

echo ""
echo -e "${INFO} Configuration Files"
echo "─────────────────────────────────────"
check ".env file present"                   "[[ -f .env ]]"
check "zabbix_server.conf present"          "[[ -f config/zabbix/zabbix_server.conf ]]"
check "ossec.conf present"                  "[[ -f config/wazuh/ossec.conf ]]"
check "local_rules.xml present"             "[[ -f config/wazuh/rules/local_rules.xml ]]"
check "elasticsearch.yml present"           "[[ -f config/elasticsearch/elasticsearch.yml ]]"
check "kibana.yml present"                  "[[ -f config/kibana/kibana.yml ]]"
check "alert_templates.json present"        "[[ -f config/alerting/alert_templates.json ]]"

echo ""
echo "============================================================"
echo -e "  Results: ${GREEN}${PASSED} passed${NC} | ${RED}${FAILED} failed${NC} | Total: ${TOTAL}"
echo "============================================================"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${WARN} Some checks failed. Review the output above."
    echo "  Useful commands:"
    echo "    docker-compose logs <service>    # View service logs"
    echo "    docker-compose ps                # View service status"
    echo "    docker-compose restart <service> # Restart a service"
    exit 1
else
    echo -e "${GREEN}All health checks passed! SOC Platform is operational.${NC}"
    exit 0
fi
