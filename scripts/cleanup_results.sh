#!/bin/bash
# Results Directory Cleanup Script
# Removes obsolete test data while preserving validation evidence

set -e

echo "============================================================"
echo "Results Directory Cleanup - EPH v5.6"
echo "============================================================"
echo ""

# Safety check
if [ ! -d "results" ]; then
    echo "❌ Error: results directory not found"
    exit 1
fi

cd results

echo "📊 Current disk usage:"
du -sh . 2>/dev/null
echo ""

# ===== FILES TO DELETE =====

echo "🗑️  Removing obsolete files..."

# 1. Temporary test file (12MB)
if [ -f "test_official_implementation.h5" ]; then
    echo "  - test_official_implementation.h5 (12MB)"
    rm test_official_implementation.h5
fi

# 2. Old diagnostic tests (112MB total)
if [ -d "diagnostic_test_20260111_103149" ]; then
    echo "  - diagnostic_test_20260111_103149/ (56MB)"
    rm -rf diagnostic_test_20260111_103149
fi

if [ -d "diagnostic_test_20260111_103506" ]; then
    echo "  - diagnostic_test_20260111_103506/ (56MB)"
    rm -rf diagnostic_test_20260111_103506
fi

# 3. Empty/failed test directory
if [ -d "theory_comparison_20260111_112223" ]; then
    echo "  - theory_comparison_20260111_112223/ (empty)"
    rm -rf theory_comparison_20260111_112223
fi

# 4. Old Phase 5 test runs
echo "  - phase5/extreme_test_* (old tests)"
rm -rf phase5/extreme_test_20260111_* 2>/dev/null || true

echo "  - phase5/test_run_* (old tests)"
rm -rf phase5/test_run_20260111_* 2>/dev/null || true

# 5. Empty directories
echo "  - Empty directories"
rmdir comparison 2>/dev/null || true
rmdir control_integration 2>/dev/null || true
rmdir data_collection 2>/dev/null || true
rmdir hyperparameter_tuning 2>/dev/null || true
rmdir haze_sensitivity 2>/dev/null || true
rmdir self_hazing 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""

echo "📊 Disk usage after cleanup:"
du -sh . 2>/dev/null
echo ""

echo "📁 Remaining structure:"
echo "├── *.md (4 validation reports) ✅ KEPT"
echo "├── theory_comparison_20260111_112249/ (260,777x evidence) ✅ KEPT"
echo "├── phase5/haze_comparison_20260111_114422/ (Active Phase 5) ✅ KEPT"
echo "├── spm_analysis/ (mechanism analysis) ✅ KEPT"
echo "├── vae_tuning/ (hyperparameter records) ✅ KEPT"
echo "├── vae_training/ (VAE metadata) ✅ KEPT"
echo "└── vae_validation/ (VAE validation) ✅ KEPT"
echo ""

cd ..
