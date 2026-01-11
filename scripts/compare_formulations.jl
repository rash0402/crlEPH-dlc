#!/usr/bin/env julia

"""
Compare Theory-Correct vs Simplified FE Formulation Results

Analyzes diagnostic metrics from both formulations to determine:
1. Which formulation shows Haze sensitivity
2. Magnitude of differences in F_safety and S(u)
3. Behavioral impact (collision rates, success rates)
"""

using HDF5
using Statistics
using Printf

function load_diagnostic_summary(filepath)
    """Load and summarize diagnostic data from HDF5"""
    h5open(filepath, "r") do file
        # Read diagnostic arrays
        betas = read(file, "betas")  # (n_steps, n_agents, 2)
        precisions = read(file, "precisions")  # (n_steps, n_agents)
        spm_stats = read(file, "spm_statistics")  # (n_steps, n_agents, 11)
        free_energies = read(file, "free_energies")  # (n_steps, n_agents, 4)

        # Compute summary statistics
        beta_r_mean = mean(betas[:, :, 1])
        beta_nu_mean = mean(betas[:, :, 2])
        precision_mean = mean(precisions)

        # SPM statistics indices: [ch1_mean, ch1_std, ch1_max, ch2_mean, ch2_std, ch2_max, ch2_var, ch3_mean, ch3_std, ch3_max, ch3_var]
        ch1_mean = mean(spm_stats[:, :, 1])
        ch2_mean = mean(spm_stats[:, :, 4])
        ch2_var = mean(spm_stats[:, :, 7])
        ch3_mean = mean(spm_stats[:, :, 8])
        ch3_var = mean(spm_stats[:, :, 11])

        # Free Energy components: [F_goal, F_safety, S_u, F_total]
        F_goal_mean = mean(free_energies[:, :, 1])
        F_safety_mean = mean(free_energies[:, :, 2])
        S_u_mean = mean(free_energies[:, :, 3])
        F_total_mean = mean(free_energies[:, :, 4])

        # Read attributes
        attr_dict = attrs(file)
        haze = attr_dict["haze_fixed"]

        return Dict(
            "haze" => haze,
            "beta_r" => beta_r_mean,
            "beta_nu" => beta_nu_mean,
            "precision" => precision_mean,
            "ch1_mean" => ch1_mean,
            "ch2_mean" => ch2_mean,
            "ch2_var" => ch2_var,
            "ch3_mean" => ch3_mean,
            "ch3_var" => ch3_var,
            "F_goal" => F_goal_mean,
            "F_safety" => F_safety_mean,
            "S_u" => S_u_mean,
            "F_total" => F_total_mean
        )
    end
end

function main()
    if length(ARGS) < 1
        println("Usage: julia compare_formulations.jl <results_directory>")
        println()
        println("Analyzes results from test_theory_vs_simplified.jl")
        exit(1)
    end

    results_dir = ARGS[1]

    println("="^80)
    println("Theory-Correct vs Simplified Formulation Comparison Report")
    println("="^80)
    println()

    # Find all result files
    simplified_files = filter(f -> startswith(basename(f), "Simplified_"),
                             readdir(results_dir, join=true))
    theory_files = filter(f -> startswith(basename(f), "Theory-Correct_"),
                         readdir(results_dir, join=true))

    if isempty(simplified_files) || isempty(theory_files)
        println("❌ Error: Could not find result files in $results_dir")
        println("   Expected files starting with 'Simplified_' and 'Theory-Correct_'")
        exit(1)
    end

    # Load and group by Haze value
    simplified_results = Dict{Float64, Vector{Dict}}()
    theory_results = Dict{Float64, Vector{Dict}}()

    for file in simplified_files
        summary = load_diagnostic_summary(file)
        haze = summary["haze"]
        if !haskey(simplified_results, haze)
            simplified_results[haze] = []
        end
        push!(simplified_results[haze], summary)
    end

    for file in theory_files
        summary = load_diagnostic_summary(file)
        haze = summary["haze"]
        if !haskey(theory_results, haze)
            theory_results[haze] = []
        end
        push!(theory_results[haze], summary)
    end

    # Compare results for each Haze value
    haze_values = sort(collect(keys(simplified_results)))

    println("Loaded data:")
    println("  Simplified formulation: $(length(simplified_files)) files")
    println("  Theory-correct formulation: $(length(theory_files)) files")
    println("  Haze values: $haze_values")
    println()

    # Generate comparison table
    println("="^80)
    println("SIMPLIFIED FORMULATION")
    println("="^80)
    println()
    @printf "%-6s  %-8s  %-8s  %-10s  %-10s  %-10s  %-10s\n" "Haze" "β_r" "Ch2_Var" "F_goal" "F_safety" "S(u)" "F_total"
    println("-"^80)

    for haze in haze_values
        runs = simplified_results[haze]
        beta_r = mean([r["beta_r"] for r in runs])
        ch2_var = mean([r["ch2_var"] for r in runs])
        F_goal = mean([r["F_goal"] for r in runs])
        F_safety = mean([r["F_safety"] for r in runs])
        S_u = mean([r["S_u"] for r in runs])
        F_total = mean([r["F_total"] for r in runs])

        @printf "%-6.1f  %-8.2f  %-8.5f  %-10.4f  %-10.4f  %-10.4f  %-10.4f\n" haze beta_r ch2_var F_goal F_safety S_u F_total
    end

    println()
    println("="^80)
    println("THEORY-CORRECT FORMULATION")
    println("="^80)
    println()
    @printf "%-6s  %-8s  %-8s  %-10s  %-10s  %-10s  %-10s\n" "Haze" "β_r" "Ch2_Var" "F_goal" "F_safety" "S(u)" "F_total"
    println("-"^80)

    for haze in haze_values
        runs = theory_results[haze]
        beta_r = mean([r["beta_r"] for r in runs])
        ch2_var = mean([r["ch2_var"] for r in runs])
        F_goal = mean([r["F_goal"] for r in runs])
        F_safety = mean([r["F_safety"] for r in runs])
        S_u = mean([r["S_u"] for r in runs])
        F_total = mean([r["F_total"] for r in runs])

        @printf "%-6.1f  %-8.2f  %-8.5f  %-10.4f  %-10.4f  %-10.4f  %-10.4f\n" haze beta_r ch2_var F_goal F_safety S_u F_total
    end

    println()
    println("="^80)
    println("HAZE SENSITIVITY ANALYSIS")
    println("="^80)
    println()

    # Compute Haze effect (H=0 → H=1) for each formulation
    if haskey(simplified_results, 0.0) && haskey(simplified_results, 1.0)
        println("Simplified Formulation (H=0.0 → H=1.0):")
        s0 = simplified_results[0.0]
        s1 = simplified_results[1.0]

        ΔF_safety_s = mean([r["F_safety"] for r in s1]) - mean([r["F_safety"] for r in s0])
        ΔS_u_s = mean([r["S_u"] for r in s1]) - mean([r["S_u"] for r in s0])
        ΔF_total_s = mean([r["F_total"] for r in s1]) - mean([r["F_total"] for r in s0])

        @printf "  ΔF_safety:  %+.6f  (%.2f%%)\n" ΔF_safety_s 100*ΔF_safety_s/mean([r["F_safety"] for r in s0])
        @printf "  ΔS(u):      %+.6f  (%.2f%%)\n" ΔS_u_s 100*ΔS_u_s/mean([r["S_u"] for r in s0])
        @printf "  ΔF_total:   %+.6f  (%.2f%%)\n" ΔF_total_s 100*ΔF_total_s/mean([r["F_total"] for r in s0])
        println()
    end

    if haskey(theory_results, 0.0) && haskey(theory_results, 1.0)
        println("Theory-Correct Formulation (H=0.0 → H=1.0):")
        t0 = theory_results[0.0]
        t1 = theory_results[1.0]

        ΔF_safety_t = mean([r["F_safety"] for r in t1]) - mean([r["F_safety"] for r in t0])
        ΔS_u_t = mean([r["S_u"] for r in t1]) - mean([r["S_u"] for r in t0])
        ΔF_total_t = mean([r["F_total"] for r in t1]) - mean([r["F_total"] for r in t0])

        @printf "  ΔF_safety:  %+.6f  (%.2f%%)\n" ΔF_safety_t 100*ΔF_safety_t/mean([r["F_safety"] for r in t0])
        @printf "  ΔS(u):      %+.6f  (%.2f%%)\n" ΔS_u_t 100*ΔS_u_t/mean([r["S_u"] for r in t0])
        @printf "  ΔF_total:   %+.6f  (%.2f%%)\n" ΔF_total_t 100*ΔF_total_t/mean([r["F_total"] for r in t0])
        println()
    end

    println("="^80)
    println("CONCLUSION")
    println("="^80)
    println()

    if haskey(simplified_results, 0.0) && haskey(simplified_results, 1.0) &&
       haskey(theory_results, 0.0) && haskey(theory_results, 1.0)

        s0 = simplified_results[0.0]
        s1 = simplified_results[1.0]
        t0 = theory_results[0.0]
        t1 = theory_results[1.0]

        ΔF_total_s = abs(mean([r["F_total"] for r in s1]) - mean([r["F_total"] for r in s0]))
        ΔF_total_t = abs(mean([r["F_total"] for r in t1]) - mean([r["F_total"] for r in t0]))

        println("Haze Effect on F_total:")
        @printf "  Simplified:     %.6f\n" ΔF_total_s
        @printf "  Theory-Correct: %.6f\n" ΔF_total_t
        println()

        if ΔF_total_t > 2.0 * ΔF_total_s
            println("✅ VALIDATION: Theory-correct formulation shows SIGNIFICANTLY higher")
            println("   Haze sensitivity ($(round(ΔF_total_t/ΔF_total_s, digits=1))x stronger effect)")
            println()
            println("Recommendation:")
            println("  → Use theory-correct formulation for Phase 5 experiments")
            println("  → Expect observable Haze-dependent behavior")
        elseif ΔF_total_t > ΔF_total_s
            println("⚠️  CAUTION: Theory-correct formulation shows moderately higher")
            println("   Haze sensitivity ($(round(ΔF_total_t/ΔF_total_s, digits=1))x stronger)")
            println()
            println("Recommendation:")
            println("  → Further investigation needed")
            println("  → Consider extreme Haze ranges (0.0-2.0)")
        else
            println("❌ UNEXPECTED: Theory-correct formulation does NOT show higher")
            println("   Haze sensitivity")
            println()
            println("Recommendation:")
            println("  → Debug theory-correct implementation")
            println("  → Verify potential function parameters")
        end
    end

    println()
    println("="^80)
end

main()
