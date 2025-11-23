#!/bin/bash
#
# EPH Quick Diagnostic Experiment
#
# Runs a single short experiment (100 steps) with diagnostic analysis
# Useful for quick testing and validation
#
# Usage:
#   ./scripts/run_quick_diagnostic.sh
#

set -e

JULIA_BIN="${HOME}/.juliaup/bin/julia"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${PROJECT_DIR}/src_julia"

echo "═══════════════════════════════════════════════════════════"
echo "  EPH Quick Diagnostic Experiment"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Running 100-step test experiment with comprehensive diagnostics..."
echo ""

cd "${SRC_DIR}"
"${JULIA_BIN}" --project=. test_logging.jl

echo ""
echo "✓ Quick diagnostic complete!"
