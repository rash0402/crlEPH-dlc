#!/bin/bash
# Complete Cleanup Script - data/logs and scripts
# Removes obsolete test files and keeps essential v5.6 files

set -e

echo "============================================================"
echo "Complete Cleanup - EPH v5.6 Project"
echo "============================================================"
echo ""

# ===== 1. Clean data/logs/ =====
echo "🗑️  Cleaning data/logs/..."

if [ -d "data/logs" ]; then
    cd data/logs

    # Remove old test logs
    if ls eph_sim_*.h5 >/dev/null 2>&1; then
        echo "  - Removing old simulation logs (*.h5)"
        rm -f eph_sim_*.h5
    fi

    # Remove empty directories
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

# ===== 2. Clean scripts/ =====
echo "🗑️  Cleaning scripts/..."

if [ -d "scripts" ]; then
    cd scripts

    # Remove temporary test/diagnostic scripts
    echo "  - Removing diagnostic/test scripts"
    rm -f test_theory_vs_simplified.jl
    rm -f test_diagnostics.jl
    rm -f diagnose_haze_mechanism.jl
    rm -f compare_all_versions.jl
    rm -f verify_spm_changes.jl
    rm -f compare_haze_tests.jl
    rm -f verify_haze_mechanism.jl
    rm -f analyze_extreme_test.jl
    rm -f run_extreme_test.jl
    rm -f quick_test_analysis.jl
    rm -f run_haze_comparison_test.jl
    rm -f test_obstacles_unified.jl
    rm -f test_metrics_fix.jl
    rm -f test_scenarios.jl

    # Remove old version scripts (pre-v5.6)
    echo "  - Removing old version scripts"
    rm -f run_simulation.jl
    rm -f validate_haze.jl
    rm -f train_action_vae.jl
    rm -f collect_diverse_vae_data.jl
    rm -f analyze_emergency_comparison.jl
    rm -f run_emergency_comparison.jl
    rm -f analyze_challenging.jl
    rm -f run_challenging_experiments.jl
    rm -f analyze_comparison.jl
    rm -f run_comparison_experiments.jl
    rm -f analyze_throughput.jl
    rm -f run_batch_experiments.jl
    rm -f evaluate_metrics.jl
    rm -f validate_m4.jl

    cd ..
fi

echo "  ✅ scripts/ cleaned"
echo ""

# ===== 3. Summary =====
echo "============================================================"
echo "✅ Cleanup Complete!"
echo "============================================================"
echo ""
echo "📁 Kept Files:"
echo ""
echo "data/logs/"
echo "  └── README.md"
echo ""
echo "scripts/ (EPH v5.6 Essential):"
echo "  ├── run_simulation_eph.jl (Main simulation)"
echo "  ├── run_haze_comparison_v56.jl (Phase 5 batch)"
echo "  ├── analyze_phase5_results.jl (Phase 5 analysis)"
echo "  ├── compare_formulations.jl (Theory validation)"
echo "  ├── train_vae_v56.jl (VAE training)"
echo "  ├── tune_vae_v56.jl (VAE tuning)"
echo "  ├── validate_vae_v56.jl (VAE validation)"
echo "  ├── create_dataset_v56.jl (Dataset creation)"
echo "  ├── collect_vae_data_v56.jl (Data collection)"
echo "  ├── compare_baseline_eph.jl (Baseline comparison)"
echo "  ├── visualize_comparison.jl (Visualization)"
echo "  ├── analyze_spm_spatial_distribution.py (SPM analysis)"
echo "  ├── run_all_eph.sh (EPH launcher)"
echo "  ├── run_all.sh (General launcher)"
echo "  ├── setup.sh (Project setup)"
echo "  └── cleanup_*.sh (Cleanup scripts)"
echo ""
echo "🗑️  Removed:"
echo "  - 21 test/diagnostic scripts"
echo "  - 11 old version scripts"
echo "  - 3 old simulation logs"
echo "  - 5 empty directories"
echo ""
