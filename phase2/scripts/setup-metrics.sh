#!/usr/bin/env bash
# =============================================================================
# setup-metrics.sh - Setup Zabbix → Elasticsearch metrics pipeline
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

exec bash "${PHASE2_DIR}/metrics-integration/scripts/setup-metrics-pipeline.sh"
