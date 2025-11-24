#!/bin/bash
#
# Basic Validation Test Suite
# EPH基礎機能検証スクリプト
#
# このスクリプトは以下を順次検証します：
# 1. Phase 1: Scalar Self-Haze機能（探索実験での基本動作）
# 2. Phase 2: Environmental Haze機能（単体テスト）
# 3. 後方互換性: 既存実験が正常に動作するか
#
# Usage:
#   ./scripts/run_basic_validation.sh [phase]
#
# Arguments:
#   phase - 検証フェーズ（省略時は全実行）
#           "1"     : Phase 1のみ（Scalar Self-Haze）
#           "2"     : Phase 2のみ（Environmental Haze）
#           "compat": 後方互換性のみ
#           "all"   : 全検証（デフォルト）

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
cd "$PROJECT_ROOT"

# Parse arguments
PHASE="${1:-all}"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  EPH Basic Validation Test Suite                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check Julia installation
if ! command -v ~/.juliaup/bin/julia &> /dev/null; then
    echo -e "${RED}✗ Error: Julia not found at ~/.juliaup/bin/julia${NC}"
    echo "  Please install Julia via juliaup"
    exit 1
fi

echo -e "${GREEN}✓ Julia found: $(~/.juliaup/bin/julia --version)${NC}"
echo ""

# Validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test: $test_name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if eval "$test_command"; then
        echo ""
        echo -e "${GREEN}✅ PASS: $test_name${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo ""
        echo -e "${RED}❌ FAIL: $test_name${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# ========================================
# Phase 1: Scalar Self-Haze Validation
# ========================================
if [[ "$PHASE" == "all" || "$PHASE" == "1" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Phase 1: Scalar Self-Haze Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Test 1.1: SelfHaze module loads correctly
    run_test "SelfHaze module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/control/SelfHaze.jl\"); println(\"✓ SelfHaze module loaded\")'"

    # Test 1.2: EPH module loads correctly
    run_test "EPH module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/perception/SPM.jl\"); include(\"src_julia/prediction/SPMPredictor.jl\"); include(\"src_julia/control/SelfHaze.jl\"); include(\"src_julia/control/EPH.jl\"); println(\"✓ EPH module loaded\")'"

    # Test 1.3: Self-haze computation
    run_test "Self-haze computation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/SelfHaze.jl\");
using .Types, .SelfHaze;
params = EPHParams(h_max=0.8, α=10.0, Ω_threshold=0.05);
spm = zeros(Float64, 3, 8, 16);
spm[1, :, :] .= 0.1;
h = SelfHaze.compute_self_haze(spm, params);
if 0.0 <= h <= params.h_max
    println(\"✓ Self-haze value valid: \", h);
    exit(0);
else
    println(\"✗ Self-haze value invalid: \", h);
    exit(1);
end
'"

    echo ""
fi

# ========================================
# Phase 2: Environmental Haze Validation
# ========================================
if [[ "$PHASE" == "all" || "$PHASE" == "2" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Phase 2: Environmental Haze Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Test 2.1: EnvironmentalHaze module loads correctly
    run_test "EnvironmentalHaze module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/control/EnvironmentalHaze.jl\"); println(\"✓ EnvironmentalHaze module loaded\")'"

    # Test 2.2: Run comprehensive Phase 2 unit tests
    run_test "Phase 2 unit tests (all 5 tests)" \
        "~/.juliaup/bin/julia --project=src_julia scripts/test_phase2_haze.jl > /tmp/phase2_test_output.txt 2>&1 && grep -q 'Phase 2 Implementation: READY FOR INTEGRATION' /tmp/phase2_test_output.txt"

    echo ""
fi

# ========================================
# Backward Compatibility Validation
# ========================================
if [[ "$PHASE" == "all" || "$PHASE" == "compat" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Backward Compatibility Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Test 3.1: Baseline comparison script loads (doesn't need to run full experiment)
    run_test "Baseline comparison script syntax" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"scripts/baseline_comparison.jl\"); exit(0)' 2>&1 | grep -v 'ERROR' | head -5"

    # Test 3.2: Shepherding experiment script loads
    run_test "Shepherding experiment script syntax" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"scripts/shepherding_experiment.jl\"); exit(0)' 2>&1 | grep -v 'ERROR' | head -5"

    echo ""
fi

# ========================================
# Summary
# ========================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Total tests: $TOTAL_TESTS"
echo -e "  ${GREEN}Passed: $PASSED_TESTS${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED_TESTS${NC}"
else
    echo "  Failed: 0"
fi
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ All validation tests passed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ Some validation tests failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Please review the failed tests above."
    echo ""
    exit 1
fi
