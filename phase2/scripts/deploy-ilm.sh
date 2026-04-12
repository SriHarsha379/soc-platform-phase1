#!/usr/bin/env bash
# =============================================================================
# deploy-ilm.sh - Deploy Phase 2 ILM policies
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

exec bash "${PHASE2_DIR}/elasticsearch/scripts/apply-ilm.sh"
