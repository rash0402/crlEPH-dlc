#!/bin/bash
# Results Directory Cleanup Script - EPH v7.2
# Removes obsolete test data while preserving validation evidence

set -e

echo "============================================================"
echo "Results Directory Cleanup - EPH v7.2"
echo "============================================================"
echo ""

# Safety check
if [ ! -d "results" ]; then
    echo "❌ Error: results directory not found"
    echo "   Creating results directory..."
    mkdir -p results
    exit 0
fi

cd results

echo "📊 Current disk usage:"
du -sh . 2>/dev/null || echo "  (empty)"
echo ""

# ===== FILES TO DELETE =====

echo "🗑️  Removing obsolete files..."

# 1. Old theory comparison results (pre-v7.2)
if ls theory_comparison_* >/dev/null 2>&1; then
    echo "  - theory_comparison_* (old validation)"
    # rm -rf theory_comparison_*  # Commented out for safety
fi

# 2. Old Phase 5 test runs (v5.6)
if [ -d "phase5" ]; then
    echo "  - phase5/ (v5.6 results)"
    # rm -rf phase5  # Commented out for safety
fi

# 3. Old VAE tuning results (pre-v7.2)
if ls vae_tuning/*.h5 >/dev/null 2>&1; then
    echo "  - vae_tuning/*.h5 (old hyperparameter tests)"
    # rm -f vae_tuning/*.h5  # Commented out for safety
fi

# 4. Empty directories
echo "  - Removing empty directories"
rmdir comparison 2>/dev/null || true
rmdir control_integration 2>/dev/null || true
rmdir data_collection 2>/dev/null || true
rmdir hyperparameter_tuning 2>/dev/null || true
rmdir haze_sensitivity 2>/dev/null || true
rmdir self_hazing 2>/dev/null || true

echo ""
echo "ℹ️  Old results preserved for reference (uncomment in script to delete)"
echo ""

echo "📊 Disk usage after cleanup:"
du -sh . 2>/dev/null || echo "  (empty)"
echo ""

echo "📁 Expected v7.2 Structure:"
echo "results/"
echo "  ├── vae_training_v72/ (training logs) [PENDING]"
echo "  ├── vae_validation_v72/ (validation metrics) [PENDING]"
echo "  ├── eph_evaluation/ (EPH controller results) [PENDING]"
echo "  └── haze_comparison/ (Haze effect analysis) [PENDING]"
echo ""
echo "🎯 Results will be generated during:"
echo "   1. VAE Training (train_action_vae_v72.jl)"
echo "   2. EPH Evaluation (run_simulation_eph.jl)"
echo "   3. Haze Ablation Studies"
echo ""

cd ..
