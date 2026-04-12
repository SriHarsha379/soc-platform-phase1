#!/usr/bin/env bash
# =============================================================================
# setup-dashboards.sh - Import Phase 2 Kibana dashboards
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Create index patterns first, then import dashboards
bash "${PHASE2_DIR}/kibana/scripts/create-index-patterns.sh"
bash "${PHASE2_DIR}/kibana/scripts/import-dashboards.sh"
