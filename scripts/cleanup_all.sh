#!/bin/bash
# Complete Cleanup Script - EPH v7.2
# Removes temporary files and old data while keeping essential v7.2 files

set -e

echo "============================================================"
echo "Complete Cleanup - EPH v7.2 Project"
echo "============================================================"
echo ""

# ===== 1. Clean data/logs/ =====
echo "🗑️  Cleaning data/logs/..."

if [ -d "data/logs" ]; then
    cd data/logs

    # Remove old simulation logs
    if ls eph_sim_*.h5 >/dev/null 2>&1; then
        echo "  - Removing old simulation logs (*.h5)"
        rm -f eph_sim_*.h5
    fi

    # Remove empty or deprecated directories
    echo "  - Removing empty directories"
    rmdir hyperparameter_tuning 2>/dev/null || true
    rmdir self_hazing 2>/dev/null || true
    rmdir haze_sensitivity 2>/dev/null || true
    rmdir comparison 2>/dev/null || true
    rmdir control_integration 2>/dev/null || true

    cd ../..
fi

echo "  ✅ data/logs/ cleaned"
echo ""

# ===== 2. Clean old VAE training data (pre-v7.2) =====
echo "🗑️  Cleaning old training data..."

if [ -d "data/vae_training/raw_v62" ]; then
    echo "  - Removing v6.2 data (if exists)"
    # rm -rf data/vae_training/raw_v62  # Commented out for safety
fi

if [ -d "data/vae_training/raw_v63" ]; then
    echo "  - Removing v6.3 data (if exists)"
    # rm -rf data/vae_training/raw_v63  # Commented out for safety
fi

echo "  ℹ️  Old data preserved (uncomment in script to delete)"
echo ""

# ===== 3. Clean scripts/archive (optional) =====
echo "🗑️  Checking scripts/archive/..."

if [ -d "scripts/archive" ]; then
    echo "  ℹ️  Archive directory exists ($(du -sh scripts/archive 2>/dev/null | cut -f1))"
    echo "  ℹ️  Review manually if needed"
fi

echo ""

# ===== 4. Summary =====
echo "============================================================"
echo "✅ Cleanup Complete!"
echo "============================================================"
echo ""
echo "📁 Current Structure (v7.2):"
echo ""
echo "data/"
echo "  ├── logs/ (simulation logs)"
echo "  └── vae_training/"
echo "      └── raw_v72/ (9 files, 25MB) ✅ ACTIVE"
echo ""
echo "scripts/ (v7.2 Essential):"
echo "  ├── create_dataset_v72_scramble.jl"
echo "  ├── create_dataset_v72_corridor.jl"
echo "  ├── create_dataset_v72_random_obstacles.jl"
echo "  ├── train_action_vae_v72.jl ← NEXT STEP"
echo "  ├── run_simulation_eph.jl"
echo "  ├── run_simulation_v72.jl"
echo "  ├── run_viewer_v72.sh"
echo "  ├── evaluate_metrics.jl"
echo "  ├── inspect_h5.jl"
echo "  ├── remote/ (GPU execution)"
echo "  └── archive/ (deprecated files)"
echo ""
echo "models/"
echo "  └── (VAE models will be saved here)"
echo ""
echo "results/"
echo "  └── (evaluation results will be saved here)"
echo ""
echo "🎯 Next Step: julia --project=. scripts/train_action_vae_v72.jl"
echo ""
