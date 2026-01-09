#!/usr/bin/env julia

"""
Comparison Batch Experiment Runner for EPH vs Baseline
Runs simulations with both conditions for direct comparison.
"""

using Printf
using Dates
using ArgParse

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--scenario"
            help = "Scenario: 'scramble' or 'corridor'"
            arg_type = String
            default = "corridor"
    end
    return parse_args(s)
end

# Configuration
SEEDS = [1, 2, 3, 4, 5]
DENSITIES = [5, 10, 15, 20]
STEPS = 1500
CONDITIONS = [
    (id=1, name="baseline"),
    (id=4, name="eph")
]

function main()
    args = parse_commandline()
    scenario = args["scenario"]
    
    OUTPUT_BASE = "data/logs/comparison_$(scenario)"
    
    println("🚀 Starting EPH vs Baseline Comparison Experiments")
    println("   Scenario:   $scenario")
    println("   Conditions: BASELINE (1) vs EPH (4)")
    println("   Densities:  $DENSITIES")
    println("   Seeds:      $SEEDS")
    println("   Output:     $OUTPUT_BASE")
    println("=" ^ 60)

    total_runs = length(SEEDS) * length(DENSITIES) * length(CONDITIONS)
    current_run = 0

    if !isdir(OUTPUT_BASE)
        mkpath(OUTPUT_BASE)
    end
    
    log_file = joinpath(OUTPUT_BASE, "experiment_log.txt")
    
    for density in DENSITIES
        for seed in SEEDS
            for cond in CONDITIONS
                current_run += 1
                timestamp = Dates.format(Dates.now(), "HH:MM:SS")
                
                output_file = joinpath(OUTPUT_BASE, "sim_$(cond.name)_d$(density)_s$(seed).h5")
                
                cmd_str = "julia --project=. scripts/run_simulation.jl --seed $seed --density $density --steps $STEPS --condition $(cond.id) --scenario $scenario --output \"$output_file\""
                
                println("\n[$current_run/$total_runs] $timestamp | $(uppercase(cond.name)), Density=$density, Seed=$seed")
                println("   Cmd: $cmd_str")
                
                try
                    run(`bash -c "$cmd_str"`)
                    open(log_file, "a") do io
                        println(io, "$timestamp, $(cond.name), $density, $seed, SUCCESS, $output_file")
                    end
                catch e
                    @error "Run failed: $e"
                    open(log_file, "a") do io
                        println(io, "$timestamp, $(cond.name), $density, $seed, FAILED, $e")
                    end
                end
            end
        end
    end
    
    println("\n✅ Comparison experiments completed!")
    println("   Total runs: $total_runs")
    println("   Output: $OUTPUT_BASE")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
