#!/usr/bin/env julia
# Create mock test data for ablation study

using JSON
using Random

Random.seed!(42)

# Create A1 baseline results (higher freezing, higher jerk)
println("Creating A1 baseline mock data...")
for seed in 1:5
    metrics = Dict(
        "performance" => Dict(
            "success_rate" => 80.0 + randn() * 5,
            "collision_rate" => 2.0 + randn() * 0.5,
            "num_successes" => 8,
            "num_collisions" => 2
        ),
        "motion_quality" => Dict(
            "freezing_rate" => 15.0 + randn() * 3,
            "avg_jerk" => 3.5 + randn() * 0.3,
            "min_ttc" => 4.0 + randn() * 0.5,
            "num_freezing_events" => 3 + rand(0:2)
        ),
        "simulation" => Dict(
            "total_steps" => 3000,
            "total_time" => 99.0,
            "num_agents" => 10
        )
    )
    
    filename = "results/ablation/a1_baseline/seed_$(lpad(seed, 3, '0'))_metrics.json"
    open(filename, "w") do io
        JSON.print(io, metrics, 2)
    end
    println("  Created: $filename")
end

# Create A4 EPH results (lower freezing, lower jerk - meets targets)
println("\nCreating A4 EPH mock data...")
for seed in 1:5
    metrics = Dict(
        "performance" => Dict(
            "success_rate" => 85.0 + randn() * 5,
            "collision_rate" => 1.5 + randn() * 0.5,
            "num_successes" => 9,
            "num_collisions" => 1
        ),
        "motion_quality" => Dict(
            "freezing_rate" => 10.0 + randn() * 2,  # ~33% reduction
            "avg_jerk" => 2.8 + randn() * 0.2,      # ~20% reduction
            "min_ttc" => 4.5 + randn() * 0.5,
            "num_freezing_events" => 1 + rand(0:1)
        ),
        "simulation" => Dict(
            "total_steps" => 3000,
            "total_time" => 99.0,
            "num_agents" => 10
        )
    )
    
    filename = "results/ablation/a4_eph/seed_$(lpad(seed, 3, '0'))_metrics.json"
    open(filename, "w") do io
        JSON.print(io, metrics, 2)
    end
    println("  Created: $filename")
end

println("\n✅ Created 10 mock experiment results")
