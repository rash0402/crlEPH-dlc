#!/usr/bin/env julia
"""
Comprehensive Experiment Diagnostics and Analysis

This script analyzes EPH experiment logs across 4 phases:
- Phase 1: System Health (physical consistency, numerical stability)
- Phase 2: GRU Prediction Performance
- Phase 3: Gradient-Driven System Diagnostics
- Phase 4: Self-Haze Dynamics and Emergent Behaviors

Usage:
    julia scripts/analyze_experiment.jl data/logs/eph_experiment_2025-11-23_11-32-56.jld2
"""

using JLD2
using Statistics
using Printf

# ============================================================================
# PHASE 1: SYSTEM HEALTH DIAGNOSTICS
# ============================================================================

function analyze_system_health(data)
    println("╔════════════════════════════════════════════════════╗")
    println("║   PHASE 1: SYSTEM HEALTH DIAGNOSTICS              ║")
    println("╚════════════════════════════════════════════════════╝")
    println()

    # Physical Consistency
    println("📐 Physical Consistency")

    if haskey(data, "velocity_magnitudes") && !isempty(data["velocity_magnitudes"])
        vel_mags = vcat(data["velocity_magnitudes"]...)
        println("  Velocity:")
        @printf("    Mean: %.2f units/s\n", mean(vel_mags))
        @printf("    Max:  %.2f units/s\n", maximum(vel_mags))
        @printf("    Min:  %.2f units/s\n", minimum(vel_mags))

        # Check for constraint violations (max_speed = 50.0)
        violations = sum(vel_mags .> 50.0)
        if violations > 0
            println("    ⚠️  WARNING: $violations velocity constraint violations detected!")
        else
            println("    ✓ No velocity constraint violations")
        end
    end
    println()

    if haskey(data, "acceleration_magnitudes") && !isempty(data["acceleration_magnitudes"])
        accel_mags = vcat(data["acceleration_magnitudes"]...)
        valid_accel = filter(x -> x > 0.0, accel_mags)
        if !isempty(valid_accel)
            println("  Acceleration:")
            @printf("    Mean: %.2f units/s²\n", mean(valid_accel))
            @printf("    Max:  %.2f units/s²\n", maximum(valid_accel))

            # Check for constraint violations (max_accel = 100.0)
            violations = sum(valid_accel .> 100.0)
            if violations > 0
                println("    ⚠️  WARNING: $violations acceleration constraint violations!")
            else
                println("    ✓ No acceleration constraint violations")
            end
        end
    end
    println()

    if haskey(data, "toroidal_wrap_events")
        total_wraps = sum(data["toroidal_wrap_events"])
        println("  Toroidal Wrapping:")
        println("    Total boundary crossings: $total_wraps")
        @printf("    Average per timestep: %.2f\n", total_wraps / length(data["toroidal_wrap_events"]))
    end
    println()

    # Numerical Stability
    println("🔢 Numerical Stability")

    if haskey(data, "nan_inf_detected")
        nan_count = sum(data["nan_inf_detected"])
        if nan_count > 0
            println("    ❌ CRITICAL: NaN/Inf detected in $nan_count timesteps!")
        else
            println("    ✓ No NaN/Inf values detected")
        end
    end
    println()

    if haskey(data, "spm_value_ranges") && !isempty(data["spm_value_ranges"])
        spm_mins = [r[1] for r in data["spm_value_ranges"]]
        spm_maxs = [r[2] for r in data["spm_value_ranges"]]
        println("  SPM Value Ranges:")
        @printf("    Global min: %.6f\n", minimum(spm_mins))
        @printf("    Global max: %.6f\n", maximum(spm_maxs))

        if minimum(spm_mins) < -1.0 || maximum(spm_maxs) > 10.0
            println("    ⚠️  WARNING: SPM values outside expected range!")
        else
            println("    ✓ SPM values within normal range")
        end
    end
    println()

    # Overall Health Status
    print("📊 Overall System Health: ")
    if haskey(data, "nan_inf_detected") && sum(data["nan_inf_detected"]) == 0
        println("✅ HEALTHY")
    else
        println("⚠️  DEGRADED")
    end
    println()
end

# ============================================================================
# PHASE 2: GRU PREDICTION PERFORMANCE
# ============================================================================

function analyze_gru_performance(data)
    println("╔════════════════════════════════════════════════════╗")
    println("║   PHASE 2: GRU PREDICTION PERFORMANCE             ║")
    println("╚════════════════════════════════════════════════════╝")
    println()

    if !haskey(data, "prediction_errors") || isempty(data["prediction_errors"])
        println("  ⚠️  No prediction error data available")
        println()
        return
    end

    # Total Prediction Error
    pred_errors = vcat(data["prediction_errors"]...)
    valid_errors = filter(x -> x > 0.0, pred_errors)

    if isempty(valid_errors)
        println("  ℹ️  No valid prediction errors (predictor may not be active)")
        println()
        return
    end

    println("🎯 Prediction Error Analysis")
    @printf("  Total MSE:\n")
    @printf("    Mean:   %.6f\n", mean(valid_errors))
    @printf("    Median: %.6f\n", median(valid_errors))
    @printf("    Std:    %.6f\n", std(valid_errors))
    @printf("    Max:    %.6f\n", maximum(valid_errors))
    println()

    # Performance Assessment
    println("  Performance Assessment:")
    mean_error = mean(valid_errors)
    if mean_error < 0.01
        println("    ✅ EXCELLENT: Mean error < 0.01")
    elseif mean_error < 0.1
        println("    ✓ GOOD: Mean error < 0.1")
    elseif mean_error < 0.5
        println("    ⚠️  MODERATE: Mean error < 0.5")
    else
        println("    ❌ POOR: Mean error >= 0.5 (GRU may need retraining)")
    end
    println()

    # Channel-specific errors
    if haskey(data, "prediction_errors_occupancy") && !isempty(data["prediction_errors_occupancy"])
        occ_errors = vcat(data["prediction_errors_occupancy"]...)
        valid_occ = filter(x -> x > 0.0, occ_errors)
        if !isempty(valid_occ)
            println("  Occupancy Channel:")
            @printf("    Mean MSE: %.6f\n", mean(valid_occ))
        end
    end

    if haskey(data, "prediction_errors_velocity") && !isempty(data["prediction_errors_velocity"])
        vel_errors = vcat(data["prediction_errors_velocity"]...)
        valid_vel = filter(x -> x > 0.0, vel_errors)
        if !isempty(valid_vel)
            println("  Velocity Channel:")
            @printf("    Mean MSE: %.6f\n", mean(valid_vel))
        end
    end
    println()

    # Hidden State Analysis
    if haskey(data, "hidden_state_norms") && !isempty(data["hidden_state_norms"])
        h_norms = vcat(data["hidden_state_norms"]...)
        valid_h = filter(x -> x > 0.0, h_norms)
        if !isempty(valid_h)
            println("🧠 Hidden State Analysis")
            @printf("  ||h|| statistics:\n")
            @printf("    Mean: %.4f\n", mean(valid_h))
            @printf("    Std:  %.4f\n", std(valid_h))
            println()
        end
    end

    if haskey(data, "hidden_state_saturation") && !isempty(data["hidden_state_saturation"])
        saturation = vcat(data["hidden_state_saturation"]...)
        valid_sat = filter(x -> x > 0.0, saturation)
        if !isempty(valid_sat)
            mean_sat = mean(valid_sat)
            @printf("  Saturation rate: %.2f%%\n", mean_sat * 100)
            if mean_sat > 0.8
                println("    ⚠️  WARNING: High saturation (>80%) - model capacity may be insufficient")
            else
                println("    ✓ Saturation within acceptable range")
            end
            println()
        end
    end
end

# ============================================================================
# PHASE 3: GRADIENT-DRIVEN SYSTEM DIAGNOSTICS
# ============================================================================

function analyze_gradient_system(data)
    println("╔════════════════════════════════════════════════════╗")
    println("║   PHASE 3: GRADIENT-DRIVEN SYSTEM DIAGNOSTICS     ║")
    println("╚════════════════════════════════════════════════════╝")
    println()

    # Gradient Norms
    if haskey(data, "agent_gradient_norms") && !isempty(data["agent_gradient_norms"])
        grad_norms = vcat(data["agent_gradient_norms"]...)
        valid_grads = filter(x -> x > 0.0, grad_norms)

        if !isempty(valid_grads)
            println("∇ Gradient Statistics")
            @printf("  ||∇G|| (EFE gradient):\n")
            @printf("    Mean:   %.6f\n", mean(valid_grads))
            @printf("    Median: %.6f\n", median(valid_grads))
            @printf("    Max:    %.6f\n", maximum(valid_grads))

            # Check for gradient vanishing
            zero_grads = sum(grad_norms .< 1e-8)
            total_grads = length(grad_norms)
            @printf("    Zero gradients: %d / %d (%.2f%%)\n", zero_grads, total_grads,
                    100 * zero_grads / total_grads)

            if zero_grads / total_grads > 0.5
                println("    ⚠️  WARNING: >50% zero gradients - possible local minima")
            else
                println("    ✓ Gradients flowing normally")
            end
            println()
        end
    end

    # Action Continuity
    if haskey(data, "action_continuity") && !isempty(data["action_continuity"])
        action_cont = vcat(data["action_continuity"]...)
        valid_cont = filter(x -> x > 0.0, action_cont)

        if !isempty(valid_cont)
            println("🎬 Action Continuity")
            @printf("  ||a_t - a_{t-1}||:\n")
            @printf("    Mean: %.4f\n", mean(valid_cont))
            @printf("    Max:  %.4f\n", maximum(valid_cont))

            # Check for jitter
            if mean(valid_cont) > 10.0
                println("    ⚠️  WARNING: High action discontinuity - possible numerical instability")
            else
                println("    ✓ Actions changing smoothly")
            end
            println()
        end
    end

    # EFE Improvement Rate
    if haskey(data, "efe_improvement_rate") && !isempty(data["efe_improvement_rate"])
        efe_improve = vcat(data["efe_improvement_rate"]...)
        valid_improve = filter(!isnan, efe_improve)

        if !isempty(valid_improve)
            println("📈 EFE Optimization Performance")
            @printf("  Improvement rate:\n")
            @printf("    Mean:   %.4f\n", mean(valid_improve))
            @printf("    Median: %.4f\n", median(valid_improve))

            # Count successful optimizations
            successful = sum(valid_improve .> 0.0)
            @printf("    Successful optimizations: %d / %d (%.2f%%)\n",
                    successful, length(valid_improve), 100 * successful / length(valid_improve))

            if successful / length(valid_improve) < 0.5
                println("    ⚠️  WARNING: <50% optimization success rate")
            else
                println("    ✓ Gradient descent performing well")
            end
            println()
        end
    end

    # Overall Assessment
    if haskey(data, "agent_efe_values") && !isempty(data["agent_efe_values"])
        efe_vals = vcat(data["agent_efe_values"]...)
        if !isempty(efe_vals)
            println("📊 Expected Free Energy Trends")
            @printf("  Mean EFE: %.4f\n", mean(efe_vals))
            @printf("  Min EFE:  %.4f\n", minimum(efe_vals))
            @printf("  Max EFE:  %.4f\n", maximum(efe_vals))
            println()
        end
    end
end

# ============================================================================
# PHASE 4: SELF-HAZE DYNAMICS & EMERGENT BEHAVIORS
# ============================================================================

function analyze_selfhaze_dynamics(data)
    println("╔════════════════════════════════════════════════════╗")
    println("║   PHASE 4: SELF-HAZE DYNAMICS & EMERGENCE         ║")
    println("╚════════════════════════════════════════════════════╝")
    println()

    if !haskey(data, "agent_self_haze_values") || isempty(data["agent_self_haze_values"])
        println("  ⚠️  No self-haze data available")
        println()
        return
    end

    # Self-Haze Statistics
    self_haze = vcat(data["agent_self_haze_values"]...)

    println("🌫️  Self-Haze Distribution")
    @printf("  Mean:   %.4f\n", mean(self_haze))
    @printf("  Median: %.4f\n", median(self_haze))
    @printf("  Std:    %.4f\n", std(self_haze))
    @printf("  Range:  [%.4f, %.4f]\n", minimum(self_haze), maximum(self_haze))
    println()

    # State Distribution (isolated vs grouped)
    isolated = sum(self_haze .> 0.5)
    grouped = sum(self_haze .<= 0.5)
    total = length(self_haze)

    println("  State Distribution:")
    @printf("    Isolated (h > 0.5): %d / %d (%.2f%%)\n", isolated, total, 100 * isolated / total)
    @printf("    Grouped  (h ≤ 0.5): %d / %d (%.2f%%)\n", grouped, total, 100 * grouped / total)
    println()

    # Transition Analysis
    if haskey(data, "self_haze_transitions") && !isempty(data["self_haze_transitions"])
        transitions = vcat(data["self_haze_transitions"]...)
        total_transitions = sum(transitions)

        println("  State Transitions:")
        println("    Total transitions: $total_transitions")
        @printf("    Transition rate: %.4f per timestep\n",
                total_transitions / length(data["self_haze_transitions"]))

        if total_transitions > 0
            println("    ✓ Dynamic self-haze modulation active")
        else
            println("    ⚠️  No transitions detected - agents may be stuck in one regime")
        end
        println()
    end

    # Occupancy vs Self-Haze
    if haskey(data, "agent_occupancy_measures") && !isempty(data["agent_occupancy_measures"])
        occupancy = vcat(data["agent_occupancy_measures"]...)

        println("  Occupancy-Haze Relationship:")
        @printf("    Mean occupancy: %.6f\n", mean(occupancy))

        # Compute correlation
        if length(self_haze) == length(occupancy)
            corr = cor(occupancy, self_haze)
            @printf("    Correlation (Ω vs h): %.4f\n", corr)

            if corr < -0.5
                println("    ✓ Strong negative correlation (expected: high occupancy → low haze)")
            elseif corr > 0.5
                println("    ⚠️  Unexpected positive correlation - check self-haze computation")
            else
                println("    ℹ️  Weak correlation - complex dynamics")
            end
        end
        println()
    end

    # Velocity vs Self-Haze Correlation
    if haskey(data, "self_haze_vs_velocity") && !isempty(data["self_haze_vs_velocity"])
        haze_vel_pairs = vcat(data["self_haze_vs_velocity"]...)
        hazes = [p[1] for p in haze_vel_pairs]
        velocities = [p[2] for p in haze_vel_pairs]

        println("  Self-Haze vs Velocity:")
        @printf("    Mean velocity: %.2f units/s\n", mean(velocities))

        if length(hazes) == length(velocities)
            corr = cor(hazes, velocities)
            @printf("    Correlation (h vs v): %.4f\n", corr)

            if abs(corr) > 0.3
                println("    ℹ️  Coupling detected between self-haze and velocity")
            else
                println("    ℹ️  Weak coupling - independent dynamics")
            end
        end
        println()
    end

    # Emergent Behavior Indicators
    println("🔍 Emergent Behavior Indicators")

    # 1. Exploration vs Exploitation Balance
    if haskey(data, "coverage_history")
        coverage = data["coverage_history"]
        final_coverage = coverage[end]
        @printf("  Final coverage: %.2f%%\n", final_coverage * 100)

        if final_coverage > 0.95
            println("    ✓ Excellent exploration (>95% coverage)")
        elseif final_coverage > 0.8
            println("    ✓ Good exploration (>80% coverage)")
        else
            println("    ⚠️  Limited exploration (<80% coverage)")
        end
    end

    # 2. Collision Avoidance via Haze
    if haskey(data, "collision_count")
        total_collisions = sum(data["collision_count"])
        println("  Total collisions: $total_collisions")

        if total_collisions == 0
            println("    ✅ Perfect collision avoidance")
        else
            println("    ⚠️  Collisions detected - haze may be insufficient")
        end
    end
    println()
end

# ============================================================================
# MAIN ANALYSIS FUNCTION
# ============================================================================

function analyze_experiment(log_file::String)
    if !isfile(log_file)
        println("❌ Error: File not found: $log_file")
        return
    end

    println()
    println("═══════════════════════════════════════════════════════════")
    println("  EPH EXPERIMENT COMPREHENSIVE DIAGNOSTICS")
    println("═══════════════════════════════════════════════════════════")
    println()
    println("📁 Log file: $log_file")

    data = load(log_file)

    println("📅 Experiment: $(data["experiment_name"])")
    println("🕐 Start time: $(data["start_time"])")
    println("📊 Data points: $(length(data["steps"]))")
    println()
    println("═══════════════════════════════════════════════════════════")
    println()

    # Run all analysis phases
    analyze_system_health(data)
    println()

    analyze_gru_performance(data)
    println()

    analyze_gradient_system(data)
    println()

    analyze_selfhaze_dynamics(data)
    println()

    println("═══════════════════════════════════════════════════════════")
    println("  ANALYSIS COMPLETE")
    println("═══════════════════════════════════════════════════════════")
    println()
end

# ============================================================================
# COMMAND-LINE INTERFACE
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia scripts/analyze_experiment.jl <log_file.jld2>")
        println()
        println("Example:")
        println("  julia scripts/analyze_experiment.jl data/logs/eph_experiment_2025-11-23_11-32-56.jld2")
        exit(1)
    end

    log_file = ARGS[1]
    analyze_experiment(log_file)
end
