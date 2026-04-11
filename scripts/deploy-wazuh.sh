#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - Wazuh Deployment Script
# Usage: ./scripts/deploy-wazuh.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[WAZUH]${NC} $*"; }
warn() { echo -e "${YELLOW}[WAZUH]${NC} $*"; }
error(){ echo -e "${RED}[WAZUH]${NC} $*" >&2; }

cd "$PROJECT_ROOT"

# ── Load environment ───────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

log "Starting Wazuh deployment …"

# ── Ensure Elasticsearch is running first ──────────────────────────────────────
log "Ensuring Elasticsearch is running …"
docker-compose up -d elasticsearch

log "Waiting for Elasticsearch to be ready …"
ES_URL="http://localhost:9200"
ES_AUTH="${ELASTIC_USERNAME:-elastic}:${ELASTIC_PASSWORD:-elastic_secure_password}"

for i in $(seq 1 36); do
    if curl -sf -u "$ES_AUTH" "${ES_URL}/_cluster/health" > /dev/null 2>&1; then
        log "Elasticsearch is ready."
        break
    fi
    if [[ $i -eq 36 ]]; then
        error "Elasticsearch did not start in time."
        exit 1
    fi
    echo -n "."
    sleep 5
done

# ── Start Wazuh Manager ────────────────────────────────────────────────────────
log "Starting Wazuh Manager …"
docker-compose up -d wazuh-manager

log "Waiting for Wazuh Manager to initialize …"
for i in $(seq 1 30); do
    if docker-compose exec -T wazuh-manager /var/ossec/bin/wazuh-control status > /dev/null 2>&1; then
        log "Wazuh Manager is running."
        break
    fi
    if [[ $i -eq 30 ]]; then
        warn "Wazuh Manager may still be initializing. Check: docker-compose logs wazuh-manager"
    fi
    sleep 10
done

# ── Create Wazuh indices in Elasticsearch ─────────────────────────────────────
log "Creating Wazuh index templates in Elasticsearch …"

curl -sf -X PUT \
    -u "$ES_AUTH" \
    -H "Content-Type: application/json" \
    "${ES_URL}/_index_template/wazuh-alerts" \
    -d '{
      "index_patterns": ["wazuh-alerts-*"],
      "template": {
        "settings": {
          "number_of_shards": 1,
          "number_of_replicas": 0,
          "index.refresh_interval": "5s"
        },
        "mappings": {
          "properties": {
            "@timestamp": {"type": "date"},
            "rule": {
              "properties": {
                "level": {"type": "integer"},
                "id": {"type": "keyword"},
                "description": {"type": "text"},
                "groups": {"type": "keyword"}
              }
            },
            "agent": {
              "properties": {
                "id": {"type": "keyword"},
                "name": {"type": "keyword"},
                "ip": {"type": "ip"}
              }
            },
            "data": {
              "properties": {
                "srcip": {"type": "ip"},
                "srcuser": {"type": "keyword"},
                "dstuser": {"type": "keyword"}
              }
            }
          }
        }
      },
      "priority": 100
    }' > /dev/null 2>&1 && log "Wazuh index template created." || warn "Index template may already exist."

# ── Create ILM policy for log retention ───────────────────────────────────────
log "Creating ILM policy for Wazuh log retention (90 days) …"

curl -sf -X PUT \
    -u "$ES_AUTH" \
    -H "Content-Type: application/json" \
    "${ES_URL}/_ilm/policy/wazuh-alerts-policy" \
    -d '{
      "policy": {
        "phases": {
          "hot": {
            "min_age": "0ms",
            "actions": {
              "rollover": {
                "max_size": "10gb",
                "max_age": "7d"
              }
            }
          },
          "warm": {
            "min_age": "30d",
            "actions": {
              "forcemerge": {"max_num_segments": 1},
              "shrink": {"number_of_shards": 1}
            }
          },
          "delete": {
            "min_age": "90d",
            "actions": {
              "delete": {}
            }
          }
        }
      }
    }' > /dev/null 2>&1 && log "ILM policy created." || warn "ILM policy may already exist."

log "Wazuh deployment complete."
log "Manager API: https://localhost:55000"
log "Agent enrollment port: 1515"
warn "To enroll agents, run on the endpoint:"
warn "  curl -so /tmp/wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.0-1_amd64.deb"
warn "  WAZUH_MANAGER='<manager-ip>' dpkg -i /tmp/wazuh-agent.deb"
warn "  systemctl enable --now wazuh-agent"
