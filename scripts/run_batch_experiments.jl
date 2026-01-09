#!/usr/bin/env julia

"""
Batch Experiment Runner for EPH v5.5
Runs simulations across multiple densities and seeds.
"""

using Printf
using Dates

# Configuration
SEEDS = [1, 2, 3, 4, 5]
DENSITIES = [5, 10, 15, 20]  # Agents per group (Total = 4x)
STEPS = 1500
CONDITION = 4  # A4_EPH
OUTPUT_BASE = "data/logs/batch_experiment"

# Command template
CMD_TEMPLATE = "julia --project=. scripts/run_simulation.jl --seed %d --density %d --steps %d --condition %d --output \"%s\""

function main()
    println("🚀 Starting Batch Experiments")
    println("   Densities: $DENSITIES")
    println("   Seeds:     $SEEDS")
    println("   Condition: $CONDITION")
    println("   Output:    $OUTPUT_BASE")
    println("=" ^ 60)

    total_runs = length(SEEDS) * length(DENSITIES)
    current_run = 0

    if !isdir(OUTPUT_BASE)
        mkpath(OUTPUT_BASE)
    end
    
    # Store log of runs
    log_file = joinpath(OUTPUT_BASE, "experiment_log.txt")
    
    for density in DENSITIES
        for seed in SEEDS
            current_run += 1
            timestamp = Dates.format(Dates.now(), "HH:MM:SS")
            
            # output_file = joinpath(OUTPUT_BASE, @sprintf("sim_d%02d_s%03d.h5", density, seed)) 
            # Use @sprintf for filename is fine if literal, but let's just use string interpolation for command to be safe
            output_file = joinpath(OUTPUT_BASE, "sim_d$(density)_s$(seed).h5")
            
            cmd_str = "julia --project=. scripts/run_simulation.jl --seed $seed --density $density --steps $STEPS --condition $CONDITION --output \"$output_file\""
            
            println("\n[$current_run/$total_runs] $timestamp | Density=$density, Seed=$seed")
            println("   Cmd: $cmd_str")
            
            # Execute simulation
            # We use distinct separate processes to avoid state leakage and ensure clean runs
            try
                run(`bash -c "$cmd_str"`)
                open(log_file, "a") do io
                    println(io, "$timestamp, $density, $seed, SUCCESS, $output_file")
                end
            catch e
                @error "Run failed: $e"
                open(log_file, "a") do io
                    println(io, "$timestamp, $density, $seed, FAILED, $e")
                end
            end
        end
    end
    
    println("\n✅ Batch experiments completed!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
