"""
Experiment 3: Compactness Invariance - Haze as Modulator, Not Driver

Tests the fundamental property that Haze modulates existing forces but does not
create driving forces. Without social attraction, varying haze patterns should not
change swarm compactness (Compactness Invariance).

Environment: Open field with no obstacles
Variables:
  - Independent 1: Driving force presence (None vs Social attraction)
  - Independent 2: Haze spatial pattern (Uniform, Center, Donut)
  - Dependent: Swarm compactness (agent dispersion)
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include("../utils/MathUtils.jl")
include("../core/Types.jl")
include("../utils/ConfigLoader.jl")
include("../perception/SPM.jl")
include("../prediction/SPMPredictor.jl")
include("../control/SelfHaze.jl")
include("../control/EnvironmentalHaze.jl")
include("../control/FullTensorHaze.jl")
include("../control/EPH.jl")
include("../Simulation.jl")

using .Simulation
using .Types
using .EnvironmentalHaze
using .SPMPredictor
using JSON
using Statistics
using LinearAlgebra

"""
Initialize open field environment
"""
function initialize_open_field(;width=400.0, height=400.0, n_agents=15)
    env = Environment(width, height, grid_size=10)

    # Place agents randomly
    for i in 1:n_agents
        x = width * (0.3 + 0.4 * rand())
        y = height * (0.3 + 0.4 * rand())
        theta = rand() * 2π - π

        agent_color = (80, 120, 255)
        agent = Agent(i, x, y, theta=theta, radius=3.0, color=agent_color)
        agent.personal_space = 20.0
        agent.goal = nothing

        push!(env.agents, agent)
    end

    return env
end

"""
Apply haze pattern to environment
"""
function apply_haze_pattern!(env::Environment, pattern::String)
    cx, cy = env.width/2, env.height/2

    for gx in 1:size(env.haze_grid, 1)
        for gy in 1:size(env.haze_grid, 2)
            x = (gx - 0.5) * env.grid_size
            y = (gy - 0.5) * env.grid_size

            dist_from_center = sqrt((x - cx)^2 + (y - cy)^2)
            max_dist = sqrt(cx^2 + cy^2)

            if pattern == "uniform"
                env.haze_grid[gx, gy] = 0.5
            elseif pattern == "center"
                # High haze at center, low at edges
                env.haze_grid[gx, gy] = 0.8 * (1.0 - dist_from_center / max_dist)
            elseif pattern == "donut"
                # High haze in ring, low at center and edges
                normalized_dist = dist_from_center / max_dist
                if 0.3 < normalized_dist < 0.7
                    env.haze_grid[gx, gy] = 0.8
                else
                    env.haze_grid[gx, gy] = 0.2
                end
            end
        end
    end
end

"""
Compute swarm compactness (lower = more compact)
"""
function compute_compactness(agents::Vector{Agent})
    if length(agents) < 2
        return 0.0
    end

    # Average pairwise distance
    total_dist = 0.0
    count = 0

    for i in 1:length(agents)
        for j in (i+1):length(agents)
            dist = sqrt(sum((agents[i].position - agents[j].position).^2))
            total_dist += dist
            count += 1
        end
    end

    return total_dist / count
end

"""
Run single trial
"""
function run_trial(has_social_force::Bool, haze_pattern::String, trial_id::Int, max_steps::Int=500)
    force_label = has_social_force ? "with_social" : "no_social"
    println("Running Experiment 3 - Trial $trial_id: $force_label, $haze_pattern haze...")

    env = initialize_open_field()
    apply_haze_pattern!(env, haze_pattern)

    # Initialize EPH parameters
    config = ConfigLoader.load_config()
    params = ConfigLoader.create_eph_params(config)
    params.enable_env_haze = true
    params.haze_decay_rate = 0.0  # Keep constant haze
    params.β = has_social_force ? 1.0 : 0.0  # Social attraction weight

    predictor = SPMPredictor.LinearPredictor(params.prediction_dt)

    # Metrics tracking
    results = Dict(
        "has_social_force" => has_social_force,
        "haze_pattern" => haze_pattern,
        "trial_id" => trial_id,
        "compactness_over_time" => Float64[],
        "initial_compactness" => compute_compactness(env.agents),
        "final_compactness" => 0.0
    )

    # Add social goal if enabled
    if has_social_force
        # Set goal to swarm center
        center_x = mean(agent.position[1] for agent in env.agents)
        center_y = mean(agent.position[2] for agent in env.agents)

        for agent in env.agents
            agent.goal = [center_x, center_y]
        end
    end

    # Run simulation
    for step in 1:max_steps
        # Update swarm center goal periodically
        if has_social_force && step % 50 == 0
            center_x = mean(agent.position[1] for agent in env.agents)
            center_y = mean(agent.position[2] for agent in env.agents)

            for agent in env.agents
                agent.goal = [center_x, center_y]
            end
        end

        Simulation.step!(env, params, predictor)

        # Track compactness
        if step % 10 == 0
            compactness = compute_compactness(env.agents)
            push!(results["compactness_over_time"], compactness)
        end
    end

    results["final_compactness"] = compute_compactness(env.agents)

    return results
end

"""
Run full experiment
"""
function run_experiment(n_trials::Int=5)
    println("\n=== Experiment 3: Compactness Invariance ===")
    println("Testing Haze as modulator vs driver of swarm behavior\n")

    all_results = []

    for has_social in [false, true]
        for pattern in ["uniform", "center", "donut"]
            for trial in 1:n_trials
                result = run_trial(has_social, pattern, trial)
                push!(all_results, result)

                force_label = has_social ? "Social" : "NoSocial"
                println("  [$force_label/$pattern] Trial $trial: " *
                        "Initial=$(round(result["initial_compactness"], digits=1)), " *
                        "Final=$(round(result["final_compactness"], digits=1))")
            end
        end
    end

    # Save results
    output_dir = joinpath(@__DIR__, "../../data/experiments")
    mkpath(output_dir)

    using Dates
    output_file = joinpath(output_dir, "exp3_compactness_invariance_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")).json")

    open(output_file, "w") do f
        JSON.print(f, all_results, 2)
    end

    println("\nResults saved to: $output_file")

    # Print summary
    println("\n=== Summary Statistics ===")
    for has_social in [false, true]
        force_label = has_social ? "With Social Force" : "No Social Force"
        println("\n[$force_label]")

        for pattern in ["uniform", "center", "donut"]
            pattern_results = filter(r -> r["has_social_force"] == has_social && r["haze_pattern"] == pattern, all_results)

            avg_initial = mean(r["initial_compactness"] for r in pattern_results)
            avg_final = mean(r["final_compactness"] for r in pattern_results)
            change = avg_final - avg_initial

            println("  $pattern: Initial=$(round(avg_initial, digits=1)), " *
                    "Final=$(round(avg_final, digits=1)), " *
                    "Change=$(round(change, digits=1))")
        end
    end

    # Test compactness invariance
    println("\n=== Compactness Invariance Test ===")
    no_social_results = filter(r -> !r["has_social_force"], all_results)

    patterns_compactness = Dict()
    for pattern in ["uniform", "center", "donut"]
        pattern_results = filter(r -> r["haze_pattern"] == pattern, no_social_results)
        patterns_compactness[pattern] = mean(r["final_compactness"] for r in pattern_results)
    end

    max_diff = maximum(abs(v1 - v2) for v1 in values(patterns_compactness) for v2 in values(patterns_compactness))
    println("Maximum compactness difference across patterns (no social): $(round(max_diff, digits=2))")
    println("Invariance holds: $(max_diff < 20.0 ? "YES" : "NO")")
end

if abspath(PROGRAM_FILE) == @__FILE__
    n_trials = parse(Int, get(ENV, "N_TRIALS", "5"))
    run_experiment(n_trials)
end
