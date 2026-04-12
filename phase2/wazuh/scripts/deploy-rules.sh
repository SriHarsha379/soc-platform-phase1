#!/usr/bin/env bash
# =============================================================================
# deploy-rules.sh - Deploy Phase 2 Wazuh correlation rules
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$(cd "${SCRIPT_DIR}/../rules" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/../config" && pwd)"

WAZUH_RULES_PATH="${WAZUH_RULES_PATH:-/var/ossec/etc/rules}"
WAZUH_DECODERS_PATH="${WAZUH_DECODERS_PATH:-/var/ossec/etc/decoders}"
WAZUH_CONTAINER="${WAZUH_CONTAINER:-wazuh-manager}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

deploy_via_docker() {
  local src="$1"
  local dest_dir="$2"
  local dest_file
  dest_file="${dest_dir}/$(basename "${src}")"

  if docker ps --format '{{.Names}}' | grep -q "^${WAZUH_CONTAINER}$"; then
    info "  Deploying via Docker: $(basename "${src}")"
    docker cp "${src}" "${WAZUH_CONTAINER}:${dest_file}"
    return 0
  fi
  return 1
}

deploy_local() {
  local src="$1"
  local dest_dir="$2"
  if [[ -d "${dest_dir}" ]]; then
    info "  Deploying locally: $(basename "${src}")"
    cp "${src}" "${dest_dir}/"
    return 0
  fi
  return 1
}

deploy_file() {
  local src="$1"
  local dest_dir="$2"
  deploy_via_docker "${src}" "${dest_dir}" || deploy_local "${src}" "${dest_dir}" || {
    warn "  Cannot deploy ${src}: Docker container '${WAZUH_CONTAINER}' not running and local path '${dest_dir}' not found."
    warn "  Copy manually: cp ${src} ${dest_dir}/"
  }
}

validate_xml() {
  local file="$1"
  if command -v xmllint &>/dev/null; then
    if xmllint --noout "${file}" 2>/dev/null; then
      info "  ✓ XML valid: $(basename "${file}")"
    else
      error "  ✗ XML invalid: $(basename "${file}")"
      return 1
    fi
  else
    warn "  xmllint not found, skipping XML validation for $(basename "${file}")"
  fi
}

reload_wazuh() {
  info "Reloading Wazuh rules..."
  if docker ps --format '{{.Names}}' | grep -q "^${WAZUH_CONTAINER}$"; then
    docker exec "${WAZUH_CONTAINER}" /var/ossec/bin/wazuh-control restart 2>/dev/null || \
    docker exec "${WAZUH_CONTAINER}" /var/ossec/bin/ossec-control restart 2>/dev/null || \
    warn "Could not restart Wazuh - rules will load on next restart"
  elif command -v /var/ossec/bin/wazuh-control &>/dev/null; then
    /var/ossec/bin/wazuh-control restart
  else
    warn "Wazuh not reachable - reload manually with: /var/ossec/bin/wazuh-control restart"
  fi
}

echo ""
echo "============================================================"
echo "  SOC Platform Phase 2 - Wazuh Rules Deployment"
echo "  $(date)"
echo "============================================================"
echo ""

echo "── Step 1: Validate XML Files ──────────────────────────────"
for f in "${RULES_DIR}"/*.xml; do validate_xml "${f}"; done
for f in "${CONFIG_DIR}"/*.xml; do validate_xml "${f}"; done

echo ""
echo "── Step 2: Deploy Correlation Rules ────────────────────────"
for rule_file in "${RULES_DIR}"/*.xml; do
  deploy_file "${rule_file}" "${WAZUH_RULES_PATH}"
done

echo ""
echo "── Step 3: Deploy Custom Decoders ──────────────────────────"
deploy_file "${CONFIG_DIR}/local_decoder.xml" "${WAZUH_DECODERS_PATH}"

echo ""
echo "── Step 4: Reload Wazuh ────────────────────────────────────"
reload_wazuh

echo ""
info "Rule deployment complete."
info "Verify with: /var/ossec/bin/wazuh-logtest"
