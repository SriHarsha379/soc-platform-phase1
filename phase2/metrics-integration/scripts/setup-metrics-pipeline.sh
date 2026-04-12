#!/usr/bin/env bash
# =============================================================================
# setup-metrics-pipeline.sh - Configure Zabbix → Elasticsearch metrics flow
# SOC Platform Phase 2 - Metrics Integration
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORTER_DIR="$(cd "${SCRIPT_DIR}/../zabbix-exporter" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
ES_USER="${ELASTIC_USERNAME:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-elastic_secure_password}"
AUTH="-u ${ES_USER}:${ES_PASS}"

INSTALL_DIR="${METRICS_INSTALL_DIR:-/opt/soc-metrics-exporter}"
SERVICE_NAME="soc-metrics-exporter"
VENV_DIR="${INSTALL_DIR}/venv"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_prereqs() {
  info "Checking prerequisites..."
  local missing=()
  command -v python3 &>/dev/null || missing+=("python3")
  command -v pip3   &>/dev/null || missing+=("python3-pip")
  command -v curl   &>/dev/null || missing+=("curl")
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    error "Install with: apt-get install -y ${missing[*]}"
    exit 1
  fi
  info "Prerequisites OK."
}

setup_python_env() {
  info "Setting up Python virtual environment at ${VENV_DIR}..."
  mkdir -p "${INSTALL_DIR}"
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip -q
  "${VENV_DIR}/bin/pip" install -r "${EXPORTER_DIR}/requirements.txt" -q
  info "Python environment ready."
}

install_exporter() {
  info "Installing exporter to ${INSTALL_DIR}..."
  cp "${EXPORTER_DIR}/zabbix_to_es_exporter.py" "${INSTALL_DIR}/"
  if [[ ! -f "${INSTALL_DIR}/config.yaml" ]]; then
    cp "${EXPORTER_DIR}/config.yaml" "${INSTALL_DIR}/config.yaml"
    warn "Copied default config.yaml to ${INSTALL_DIR}/config.yaml"
    warn "Edit it to match your Zabbix and Elasticsearch settings before starting."
  else
    info "config.yaml already exists at ${INSTALL_DIR}/config.yaml - not overwriting."
  fi
}

apply_metrics_template() {
  info "Applying metrics-zabbix index template..."
  curl -sf ${AUTH} -X PUT "${ES_URL}/_index_template/metrics-zabbix" \
    -H "Content-Type: application/json" \
    -d "@${PHASE2_DIR}/elasticsearch/index-templates/metrics-zabbix-template.json" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('  OK' if r.get('acknowledged') else '  WARN: '+str(r))"

  info "Applying metrics ILM policy..."
  curl -sf ${AUTH} -X PUT "${ES_URL}/_ilm/policy/metrics-ilm-policy" \
    -H "Content-Type: application/json" \
    -d "@${PHASE2_DIR}/elasticsearch/ilm-policies/metrics-ilm-policy.json" \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('  OK' if r.get('acknowledged') else '  WARN: '+str(r))"
}

create_systemd_service() {
  if ! command -v systemctl &>/dev/null; then
    warn "systemd not found. To run the exporter manually:"
    echo "  ${VENV_DIR}/bin/python3 ${INSTALL_DIR}/zabbix_to_es_exporter.py --config ${INSTALL_DIR}/config.yaml"
    return 0
  fi

  info "Creating systemd service: ${SERVICE_NAME}..."
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=SOC Platform - Zabbix to Elasticsearch Metrics Exporter
After=network.target elasticsearch.service
Wants=elasticsearch.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${VENV_DIR}/bin/python3 ${INSTALL_DIR}/zabbix_to_es_exporter.py --config ${INSTALL_DIR}/config.yaml
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  info "Service created. Enable with:"
  echo "  systemctl enable --now ${SERVICE_NAME}"
  echo "  systemctl status ${SERVICE_NAME}"
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Metrics Pipeline Setup"
echo "  $(date)"
echo "============================================================"
echo ""

check_prereqs
setup_python_env
install_exporter

if curl -sf ${AUTH} "${ES_URL}/_cluster/health" > /dev/null 2>&1; then
  apply_metrics_template
else
  warn "Elasticsearch not reachable at ${ES_URL}. Skipping template application."
  warn "Run apply_metrics_template manually once ES is running."
fi

create_systemd_service

echo ""
info "Metrics pipeline setup complete."
info "Next: edit ${INSTALL_DIR}/config.yaml and start the exporter."
