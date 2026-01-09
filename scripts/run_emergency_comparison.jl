#!/usr/bin/env julia

"""
EPH vs Baseline Comparison with Reduced Emergency Avoidance
Tests the effect of Haze modulation when emergency avoidance is weakened.
"""

using Printf
using Dates
using ArgParse

# Configuration - Testing with reduced emergency avoidance
K_EMERGENCY_VALUES = [5.0, 10.0]  # Lower values allow more freezing
SEEDS = [1, 2, 3]
DENSITIES = [15, 20, 25]  # Higher densities for more interactions
STEPS = 1500
SCENARIO = "corridor"
CORRIDOR_WIDTH = 3.0  # Narrow corridor

CONDITIONS = [
    (id=1, name="baseline"),
    (id=4, name="eph")
]

function main()
    OUTPUT_BASE = "data/logs/comparison_emergency"
    
    println("🔬 EPH vs Baseline with Reduced Emergency Avoidance")
    println("=" ^ 60)
    println("   k_emergency values: $K_EMERGENCY_VALUES")
    println("   Densities:          $DENSITIES")
    println("   Corridor width:     $(CORRIDOR_WIDTH)m")
    println("   Seeds:              $SEEDS")
    println("=" ^ 60)

    total_runs = length(K_EMERGENCY_VALUES) * length(SEEDS) * length(DENSITIES) * length(CONDITIONS)
    current_run = 0

    if !isdir(OUTPUT_BASE)
        mkpath(OUTPUT_BASE)
    end
    
    log_file = joinpath(OUTPUT_BASE, "experiment_log.txt")
    
    for k_emerg in K_EMERGENCY_VALUES
        for density in DENSITIES
            for seed in SEEDS
                for cond in CONDITIONS
                    current_run += 1
                    timestamp = Dates.format(Dates.now(), "HH:MM:SS")
                    
                    # Filename includes k_emergency
                    output_file = joinpath(OUTPUT_BASE, "sim_$(cond.name)_k$(Int(k_emerg))_d$(density)_s$(seed).h5")
                    
                    cmd_str = "julia --project=. scripts/run_simulation.jl " *
                              "--seed $seed " *
                              "--density $density " *
                              "--steps $STEPS " *
                              "--condition $(cond.id) " *
                              "--scenario $SCENARIO " *
                              "--corridor-width $CORRIDOR_WIDTH " *
                              "--k-emergency $k_emerg " *
                              "--output \"$output_file\""
                    
                    println("\n[$current_run/$total_runs] $timestamp | $(uppercase(cond.name))")
                    println("   k_emergency=$k_emerg, Density=$density, Seed=$seed")
                    
                    try
                        run(`bash -c "$cmd_str"`)
                        open(log_file, "a") do io
                            println(io, "$timestamp,$(cond.name),$k_emerg,$density,$seed,SUCCESS,$output_file")
                        end
                    catch e
                        @error "Run failed: $e"
                        open(log_file, "a") do io
                            println(io, "$timestamp,$(cond.name),$k_emerg,$density,$seed,FAILED,$e")
                        end
                    end
                end
            end
        end
    end
    
    println("\n✅ Experiments completed!")
    println("   Total runs: $total_runs")
    println("   Output: $OUTPUT_BASE")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
