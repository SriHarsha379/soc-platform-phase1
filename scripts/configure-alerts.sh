#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Alert Configuration Script
# Usage: ./scripts/configure-alerts.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ALERTS]${NC} $*"; }
warn() { echo -e "${YELLOW}[ALERTS]${NC} $*"; }
error(){ echo -e "${RED}[ALERTS]${NC} $*" >&2; }

cd "$PROJECT_ROOT"

# ── Load environment ───────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

ES_URL="http://localhost:9200"
ES_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"
KIBANA_URL="http://localhost:5601"
KIBANA_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"

log "Configuring SOC alerting system …"

# ── Wait for Kibana ────────────────────────────────────────────────────────────
log "Waiting for Kibana to be ready …"
for i in $(seq 1 30); do
    STATUS=$(curl -sf -u "$KIBANA_AUTH" "${KIBANA_URL}/api/status" 2>/dev/null | grep -o '"level":"[^"]*"' | head -1 || echo "")
    if echo "$STATUS" | grep -q "available"; then
        log "Kibana is ready."
        break
    fi
    if [[ $i -eq 30 ]]; then
        warn "Kibana not ready – skipping Kibana configuration."
    fi
    sleep 10
done

# ── Create Kibana index patterns ───────────────────────────────────────────────
log "Creating Kibana index pattern for Wazuh alerts …"

curl -sf -X POST \
    -u "$KIBANA_AUTH" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    "${KIBANA_URL}/api/saved_objects/index-pattern/wazuh-alerts-*" \
    -d '{
      "attributes": {
        "title": "wazuh-alerts-*",
        "timeFieldName": "@timestamp"
      }
    }' > /dev/null 2>&1 && log "Wazuh index pattern created." || warn "Index pattern may already exist."

# ── Create Kibana dashboards ───────────────────────────────────────────────────
log "Creating SOC Security Events dashboard …"

DASHBOARD_ID="soc-security-events"
curl -sf -X POST \
    -u "$KIBANA_AUTH" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    "${KIBANA_URL}/api/saved_objects/dashboard/${DASHBOARD_ID}" \
    -d "{
      \"attributes\": {
        \"title\": \"SOC - Security Events Overview\",
        \"description\": \"Real-time security events from Wazuh SIEM\",
        \"panelsJSON\": \"[]\",
        \"optionsJSON\": \"{\\\"darkTheme\\\":false}\",
        \"timeRestore\": true,
        \"timeTo\": \"now\",
        \"timeFrom\": \"now-24h\",
        \"refreshInterval\": {
          \"pause\": false,
          \"value\": 30000
        }
      }
    }" > /dev/null 2>&1 && log "Security events dashboard created." || warn "Dashboard may already exist."

# ── Configure Elasticsearch watcher alerts ─────────────────────────────────────
log "Configuring Elasticsearch watcher for high CPU alerts …"

curl -sf -X PUT \
    -u "$ES_AUTH" \
    -H "Content-Type: application/json" \
    "${ES_URL}/_watcher/watch/soc_high_cpu_alert" \
    -d "{
      \"trigger\": {
        \"schedule\": { \"interval\": \"5m\" }
      },
      \"input\": {
        \"search\": {
          \"request\": {
            \"indices\": [\"wazuh-alerts-*\"],
            \"body\": {
              \"query\": {
                \"bool\": {
                  \"must\": [
                    {\"range\": {\"@timestamp\": {\"gte\": \"now-5m\"}}},
                    {\"match\": {\"rule.groups\": \"soc_critical\"}}
                  ]
                }
              }
            }
          }
        }
      },
      \"condition\": {
        \"compare\": { \"ctx.payload.hits.total.value\": { \"gt\": 0 } }
      },
      \"actions\": {
        \"log_alert\": {
          \"logging\": {
            \"level\": \"warn\",
            \"text\": \"SOC ALERT: Critical security event detected - {{ctx.payload.hits.total.value}} events\"
          }
        }
      }
    }" > /dev/null 2>&1 && log "Elasticsearch watcher configured." || warn "Watcher may require X-Pack license."

# ── Configure Zabbix SMTP alerts ───────────────────────────────────────────────
log "Configuring Zabbix SMTP media type …"

ZABBIX_URL="http://localhost:8080"
TOKEN_RESP=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"Admin\",\"password\":\"zabbix\"},\"id\":1}" \
    "${ZABBIX_URL}/api_jsonrpc.php" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$TOKEN_RESP" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

if [[ -n "$AUTH_TOKEN" ]]; then
    SMTP_HOST_VAL="${SMTP_HOST:-smtp.gmail.com}"
    SMTP_PORT_VAL="${SMTP_PORT:-587}"
    SMTP_USER_VAL="${SMTP_USER:-}"
    SMTP_FROM_VAL="${SMTP_FROM:-soc-alerts@yourdomain.com}"

    curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "{
          \"jsonrpc\":\"2.0\",
          \"method\":\"mediatype.create\",
          \"params\":{
            \"name\":\"Email (SMTP)\",
            \"type\":0,
            \"smtp_server\":\"${SMTP_HOST_VAL}\",
            \"smtp_port\":${SMTP_PORT_VAL},
            \"smtp_helo\":\"localhost\",
            \"smtp_email\":\"${SMTP_FROM_VAL}\",
            \"smtp_security\":1,
            \"smtp_authentication\":1,
            \"username\":\"${SMTP_USER_VAL}\",
            \"status\":0,
            \"message_format\":1
          },
          \"auth\":\"${AUTH_TOKEN}\",
          \"id\":2
        }" \
        "${ZABBIX_URL}/api_jsonrpc.php" > /dev/null 2>&1 && log "Zabbix SMTP media type configured." || warn "Zabbix SMTP may already be configured."
else
    warn "Could not authenticate with Zabbix API – skipping SMTP configuration."
fi

log "Alert configuration complete."
log "Check the alerting service: docker-compose logs soc-alerting"
