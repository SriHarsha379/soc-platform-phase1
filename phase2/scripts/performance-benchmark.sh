#!/usr/bin/env bash
# =============================================================================
# performance-benchmark.sh - Phase 2 Performance Benchmark
# SOC Platform - Data Analytics & Log Correlation Layer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

exec bash "${PHASE2_DIR}/elasticsearch/scripts/benchmark-queries.sh"
