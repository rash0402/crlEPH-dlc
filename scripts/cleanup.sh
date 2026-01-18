#!/bin/bash
# EPH Cleanup Script - Unified
# Combines cleanup_all.sh and cleanup_results.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all       Clean everything (logs, temp files, old data)"
    echo "  --results   Clean only results directory"
    echo "  --logs      Clean only data/logs"
    echo "  --help      Show this help message"
    echo ""
    echo "Default: --all"
}

# Parse arguments
MODE="all"
if [ $# -gt 0 ]; then
    case "$1" in
        --all)
            MODE="all"
            ;;
        --results)
            MODE="results"
            ;;
        --logs)
            MODE="logs"
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
fi

echo "============================================================"
echo "EPH Cleanup - $(echo $MODE | tr '[:lower:]' '[:upper:]')"
echo "============================================================"
echo ""

cd "$PROJECT_ROOT"

# Clean data/logs
if [ "$MODE" = "all" ] || [ "$MODE" = "logs" ]; then
    echo "🗑️  Cleaning data/logs/..."

    if [ -d "data/logs" ]; then
        cd data/logs

        # Remove old simulation logs
        if ls eph_sim_*.h5 >/dev/null 2>&1; then
            echo "  - Removing old simulation logs (*.h5)"
            rm -f eph_sim_*.h5
        fi

        # Remove empty directories
        echo "  - Removing empty directories"
        rmdir hyperparameter_tuning self_hazing haze_sensitivity comparison control_integration 2>/dev/null || true

        cd "$PROJECT_ROOT"
    fi

    echo "  ✅ data/logs/ cleaned"
    echo ""
fi

# Clean results
if [ "$MODE" = "all" ] || [ "$MODE" = "results" ]; then
    echo "🗑️  Cleaning results/..."

    if [ -d "results" ]; then
        cd results

        echo "  - Removing empty directories"
        rmdir comparison control_integration data_collection hyperparameter_tuning haze_sensitivity self_hazing 2>/dev/null || true

        cd "$PROJECT_ROOT"
    fi

    echo "  ✅ results/ cleaned"
    echo ""
fi

echo "============================================================"
echo "✅ Cleanup Complete!"
echo "============================================================"
echo ""
echo "🎯 Next Step: julia --project=. scripts/train_vae.jl"
echo ""
