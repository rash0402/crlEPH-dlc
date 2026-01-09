#!/usr/bin/env julia

"""
Challenging Corridor Comparison Experiments
Tests EPH vs Baseline under extreme conditions:
- Narrow corridors (2m, 3m)
- High density (25, 30, 35 agents per group)
"""

using Printf
using Dates
using ArgParse

# Configuration for challenging scenarios
SEEDS = [1, 2, 3]  # Reduced seeds for faster experiments
CORRIDOR_WIDTHS = [2.0, 3.0]
DENSITIES = [25, 30, 35]
STEPS = 1500
CONDITIONS = [
    (id=1, name="baseline"),
    (id=4, name="eph")
]

function main()
    OUTPUT_BASE = "data/logs/comparison_challenging"
    
    println("🔥 Starting CHALLENGING Corridor Comparison Experiments")
    println("   Corridor Widths: $CORRIDOR_WIDTHS m")
    println("   Densities:       $DENSITIES")
    println("   Seeds:           $SEEDS")
    println("   Conditions:      BASELINE (1) vs EPH (4)")
    println("   Output:          $OUTPUT_BASE")
    println("=" ^ 60)

    total_runs = length(SEEDS) * length(DENSITIES) * length(CORRIDOR_WIDTHS) * length(CONDITIONS)
    current_run = 0

    if !isdir(OUTPUT_BASE)
        mkpath(OUTPUT_BASE)
    end
    
    log_file = joinpath(OUTPUT_BASE, "experiment_log.txt")
    
    for width in CORRIDOR_WIDTHS
        for density in DENSITIES
            for seed in SEEDS
                for cond in CONDITIONS
                    current_run += 1
                    timestamp = Dates.format(Dates.now(), "HH:MM:SS")
                    
                    # Filename includes width
                    output_file = joinpath(OUTPUT_BASE, "sim_$(cond.name)_w$(Int(width))_d$(density)_s$(seed).h5")
                    
                    cmd_str = "julia --project=. scripts/run_simulation.jl --seed $seed --density $density --steps $STEPS --condition $(cond.id) --scenario corridor --corridor-width $width --output \"$output_file\""
                    
                    println("\n[$current_run/$total_runs] $timestamp | $(uppercase(cond.name)), Width=$(width)m, Density=$density, Seed=$seed")
                    println("   Cmd: $cmd_str")
                    
                    try
                        run(`bash -c "$cmd_str"`)
                        open(log_file, "a") do io
                            println(io, "$timestamp, $(cond.name), $width, $density, $seed, SUCCESS, $output_file")
                        end
                    catch e
                        @error "Run failed: $e"
                        open(log_file, "a") do io
                            println(io, "$timestamp, $(cond.name), $width, $density, $seed, FAILED, $e")
                        end
                    end
                end
            end
        end
    end
    
    println("\n✅ Challenging experiments completed!")
    println("   Total runs: $total_runs")
    println("   Output: $OUTPUT_BASE")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
