#!/bin/bash
#
# Basic Validation Test Suite
# EPH基礎機能検証スクリプト
#
# このスクリプトは以下を順次検証します：
# 1. Phase 1: Scalar Self-Haze機能（探索実験での基本動作）
# 2. Phase 2: Environmental Haze機能（単体テスト）
# 3. Phase 3: Advanced Integration（GRU予測器・Shepherding統合）
# 4. Phase 4: Full 3D Tensor Haze（チャネル毎精度制御）
#
# Usage:
#   ./scripts/run_basic_validation.sh [phase]
#
# Arguments:
#   phase - 検証フェーズ（省略時は全実行）
#           "1"     : Phase 1のみ（Scalar Self-Haze）
#           "2"     : Phase 2のみ（Environmental Haze）
#           "3"     : Phase 3のみ（Advanced Integration）
#           "4"     : Phase 4のみ（Full 3D Tensor Haze）
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
# Phase 3: Advanced Integration Validation
# ========================================
if [[ "$PHASE" == "all" || "$PHASE" == "3" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Phase 3: Advanced Integration Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Test 3.1: SPMPredictor module loads correctly
    run_test "SPMPredictor module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/perception/SPM.jl\"); include(\"src_julia/prediction/SPMPredictor.jl\"); println(\"✓ SPMPredictor module loaded\")'"

    # Test 3.2: LinearPredictor instantiation
    run_test "LinearPredictor instantiation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/perception/SPM.jl\");
include(\"src_julia/prediction/SPMPredictor.jl\");
using .SPMPredictor;
predictor = LinearPredictor(0.1);
println(\"✓ LinearPredictor created: dt=\", predictor.dt);
exit(0);
'"

    # Test 3.3: ShepherdingEPH module loads correctly
    run_test "ShepherdingEPH module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/perception/SPM.jl\"); include(\"src_julia/control/ShepherdingEPH.jl\"); println(\"✓ ShepherdingEPH module loaded\")'"

    # Test 3.4: ShepherdingParams instantiation
    run_test "ShepherdingParams instantiation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/perception/SPM.jl\");
include(\"src_julia/control/ShepherdingEPH.jl\");
using .ShepherdingEPH;
params = ShepherdingParams(w_target=1.0, w_density=0.5, w_work=0.1);
println(\"✓ ShepherdingParams created: w_target=\", params.w_target);
exit(0);
'"

    # Test 3.5: BoidsAgent module loads correctly
    run_test "BoidsAgent module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/agents/BoidsAgent.jl\"); println(\"✓ BoidsAgent module loaded\")'"

    # Test 3.6: GRU model loading (optional - won't fail if model doesn't exist)
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Test: GRU model loading (optional)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    GRU_MODEL_PATH="src_julia/prediction/models/spm_predictor.jld2"
    if [ -f "$GRU_MODEL_PATH" ]; then
        if ~/.juliaup/bin/julia --project=src_julia -e "
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/perception/SPM.jl\");
include(\"src_julia/prediction/SPMPredictor.jl\");
using .SPMPredictor;
predictor = load_predictor(\"$GRU_MODEL_PATH\");
println(\"✓ GRU model loaded successfully\");
exit(0);
" 2>&1; then
            echo ""
            echo -e "${GREEN}✅ PASS: GRU model loading${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo ""
            echo -e "${RED}❌ FAIL: GRU model loading${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo -e "${YELLOW}⚠ GRU model not found at $GRU_MODEL_PATH - skipping (this is optional)${NC}"
        echo ""
        echo -e "${GREEN}✅ PASS: GRU model loading (skipped - model not trained yet)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    echo ""

    echo ""
fi

# ========================================
# Phase 4: Full 3D Tensor Haze Validation
# ========================================
if [[ "$PHASE" == "all" || "$PHASE" == "4" ]]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Phase 4: Full 3D Tensor Haze Validation${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Test 4.1: FullTensorHaze module loads correctly
    run_test "FullTensorHaze module import" \
        "~/.juliaup/bin/julia --project=src_julia -e 'include(\"src_julia/utils/MathUtils.jl\"); include(\"src_julia/core/Types.jl\"); include(\"src_julia/control/FullTensorHaze.jl\"); println(\"✓ FullTensorHaze module loaded\")'"

    # Test 4.2: FullTensorHazeParams instantiation
    run_test "FullTensorHazeParams instantiation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/FullTensorHaze.jl\");
using .FullTensorHaze;
params = FullTensorHazeParams(w_occupancy=1.0, w_radial_vel=0.5, w_tangential_vel=0.5);
println(\"✓ FullTensorHazeParams created: w_occ=\", params.w_occupancy);
exit(0);
'"

    # Test 4.3: Full tensor haze computation
    run_test "Full tensor haze computation (3D)" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/FullTensorHaze.jl\");
using .FullTensorHaze;
params = FullTensorHazeParams();
spm = zeros(Float64, 3, 8, 16);
spm[1, :, :] .= 0.1;  # Occupancy
spm[2, :, :] .= 0.05; # Radial velocity
spm[3, :, :] .= 0.05; # Tangential velocity
haze_tensor = compute_full_tensor_haze(spm, params);
if size(haze_tensor) == (3, 8, 16) && all(0.0 .<= haze_tensor .<= 1.0)
    println(\"✓ Haze tensor valid: size=\", size(haze_tensor));
    println(\"  Channel 1 (occ) haze: \", round(haze_tensor[1,1,1], digits=3));
    println(\"  Channel 2 (rad) haze: \", round(haze_tensor[2,1,1], digits=3));
    println(\"  Channel 3 (tan) haze: \", round(haze_tensor[3,1,1], digits=3));
    exit(0);
else
    println(\"✗ Haze tensor invalid\");
    exit(1);
end
'"

    # Test 4.4: Per-channel precision computation
    run_test "Per-channel precision computation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
using Statistics;
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/FullTensorHaze.jl\");
using .FullTensorHaze;
params = FullTensorHazeParams();
spm = zeros(Float64, 3, 8, 16);
spm[1, :, :] .= 0.1;
haze_tensor = compute_full_tensor_haze(spm, params);
precision_tensor = compute_channel_precision(spm, haze_tensor, params);
if size(precision_tensor) == (3, 8, 16) && all(0.0 .<= precision_tensor .<= 1.0)
    println(\"✓ Precision tensor valid: size=\", size(precision_tensor));
    println(\"  Mean precision (channel 1): \", round(mean(precision_tensor[1,:,:]), digits=3));
    exit(0);
else
    println(\"✗ Precision tensor invalid\");
    exit(1);
end
'"

    # Test 4.5: Channel mask application
    run_test "Channel mask application" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/FullTensorHaze.jl\");
using .FullTensorHaze;
params = FullTensorHazeParams();
spm = zeros(Float64, 3, 8, 16);
spm .= 0.1;
haze_tensor = compute_full_tensor_haze(spm, params);
# Mask: ignore occupancy, focus on velocity
channel_mask = [0.0, 1.0, 1.0];
masked_haze = apply_channel_mask(haze_tensor, channel_mask);
if masked_haze[1,1,1] ≈ 0.0 && masked_haze[2,1,1] > 0.0
    println(\"✓ Channel mask applied correctly\");
    println(\"  Occupancy haze (masked): \", round(masked_haze[1,1,1], digits=3));
    println(\"  Radial vel haze (active): \", round(masked_haze[2,1,1], digits=3));
    exit(0);
else
    println(\"✗ Channel mask application failed\");
    exit(1);
end
'"

    # Test 4.6: Weighted surprise computation
    run_test "Weighted surprise computation" \
        "~/.juliaup/bin/julia --project=src_julia -e '
include(\"src_julia/utils/MathUtils.jl\");
include(\"src_julia/core/Types.jl\");
include(\"src_julia/control/FullTensorHaze.jl\");
using .FullTensorHaze;
using Statistics;
params = FullTensorHazeParams();
spm_current = rand(Float64, 3, 8, 16) .* 0.2;
spm_previous = rand(Float64, 3, 8, 16) .* 0.2;
haze_tensor = compute_full_tensor_haze(spm_current, params);
precision_tensor = compute_channel_precision(spm_current, haze_tensor, params);
channel_weights = [1.0, 0.5, 0.5];
surprise = compute_weighted_surprise(spm_current, spm_previous, precision_tensor, channel_weights);
if surprise >= 0.0 && isfinite(surprise)
    println(\"✓ Weighted surprise computed: \", round(surprise, digits=4));
    exit(0);
else
    println(\"✗ Surprise computation failed: \", surprise);
    exit(1);
end
'"

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
