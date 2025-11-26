"""
Experiment 2: Epistemic Exploration Driven by Uncertainty

Tests whether haze-driven exploration follows the gradient of uncertainty
(information gaps) rather than random wandering.

Environment: Open field with unknown regions (high haze zones)
Comparison:
  - EPH agent: Exploration driven by belief entropy increase
  - Random baseline: Gaussian noise added to actions
Variables:
  - Independent: Controller type (EPH vs Random)
  - Dependent: Time to reach unknown region, coverage efficiency, trajectory directedness
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
using .EPH
using JSON
using Statistics
using LinearAlgebra

"""
Initialize exploration environment with unknown regions
"""
function initialize_exploration_env(;width=600.0, height=600.0, n_agents=3)
    env = Environment(width, height, grid_size=10)

    # Place agents in the center of known region (low haze)
    for i in 1:n_agents
        x = width * 0.25
        y = height/2 + (i - (n_agents+1)/2) * 30.0
        theta = rand() * 2π - π

        agent_color = (80, 120, 255)
        agent = Agent(i, x, y, theta=theta, radius=3.0, color=agent_color)
        agent.personal_space = 20.0
        agent.goal = nothing  # No explicit goal

        push!(env.agents, agent)
    end

    # Create unknown region (high haze zone) on the right side
    for gx in 1:size(env.haze_grid, 1)
        for gy in 1:size(env.haze_grid, 2)
            x = (gx - 0.5) * env.grid_size
            y = (gy - 0.5) * env.grid_size

            # Unknown region: right half of the field
            if x > width * 0.5
                env.haze_grid[gx, gy] = 0.8  # High uncertainty
            else
                env.haze_grid[gx, gy] = 0.1  # Known region
            end
        end
    end

    return env
end

"""
Run single trial with specified controller type
"""
function run_trial(controller_type::String, trial_id::Int, max_steps::Int=1000)
    println("Running Experiment 2 - Trial $trial_id with $controller_type controller...")

    env = initialize_exploration_env()

    # Initialize EPH parameters
    config = ConfigLoader.load_config()
    params = ConfigLoader.create_eph_params(config)
    params.enable_env_haze = true
    params.haze_decay_rate = 0.99  # Gradual decay as explored
    params.λ = controller_type == "eph" ? 0.5 : 0.0  # Epistemic weight

    predictor = SPMPredictor.LinearPredictor(params.prediction_dt)

    # Metrics tracking
    results = Dict(
        "controller_type" => controller_type,
        "trial_id" => trial_id,
        "time_to_unknown" => 0,
        "coverage_over_time" => Float64[],
        "trajectory_directedness" => Float64[],
        "visited_cells" => Set{Tuple{Int,Int}}()
    )

    unknown_reached = false

    # Run simulation
    for step in 1:max_steps
        # Apply random noise for baseline
        if controller_type == "random"
            for agent in env.agents
                noise = randn(2) * 10.0  # Gaussian noise
                agent.velocity .+= noise
                agent.velocity = min.(max.(agent.velocity, -params.max_speed), params.max_speed)
            end
        end

        Simulation.step!(env, params, predictor)

        # Track coverage
        for agent in env.agents
            gx = clamp(floor(Int, agent.position[1] / env.grid_size) + 1, 1, size(env.haze_grid, 1))
            gy = clamp(floor(Int, agent.position[2] / env.grid_size) + 1, 1, size(env.haze_grid, 2))
            push!(results["visited_cells"], (gx, gy))

            # Check if reached unknown region
            if !unknown_reached && agent.position[1] > env.width * 0.5
                results["time_to_unknown"] = step
                unknown_reached = true
            end

            # Compute trajectory directedness (alignment with haze gradient)
            if norm(agent.velocity) > 0.1
                # Find nearest high-haze cell
                min_dist = Inf
                nearest_haze_dir = [0.0, 0.0]

                for hx in 1:size(env.haze_grid, 1)
                    for hy in 1:size(env.haze_grid, 2)
                        if env.haze_grid[hx, hy] > 0.5
                            hx_world = (hx - 0.5) * env.grid_size
                            hy_world = (hy - 0.5) * env.grid_size
                            dist = sqrt((hx_world - agent.position[1])^2 + (hy_world - agent.position[2])^2)

                            if dist < min_dist
                                min_dist = dist
                                nearest_haze_dir = [hx_world - agent.position[1], hy_world - agent.position[2]]
                            end
                        end
                    end
                end

                if norm(nearest_haze_dir) > 0
                    directedness = dot(agent.velocity, nearest_haze_dir) / (norm(agent.velocity) * norm(nearest_haze_dir))
                    push!(results["trajectory_directedness"], directedness)
                end
            end
        end

        # Track coverage efficiency
        coverage_rate = length(results["visited_cells"]) / length(env.haze_grid)
        push!(results["coverage_over_time"], coverage_rate)
    end

    # Compute summary metrics
    results["final_coverage"] = length(results["visited_cells"]) / length(env.haze_grid)
    results["avg_directedness"] = isempty(results["trajectory_directedness"]) ? 0.0 : mean(results["trajectory_directedness"])

    delete!(results, "visited_cells")  # Remove set for JSON serialization
    delete!(results, "trajectory_directedness")  # Too large

    return results
end

"""
Run full experiment
"""
function run_experiment(n_trials::Int=10)
    println("\n=== Experiment 2: Epistemic Exploration ===")
    println("Testing Haze-driven exploration vs random wandering\n")

    all_results = []

    for controller_type in ["eph", "random"]
        for trial in 1:n_trials
            result = run_trial(controller_type, trial)
            push!(all_results, result)

            println("  [$controller_type] Trial $trial: TimeToUnknown=$(result["time_to_unknown"]), " *
                    "Coverage=$(round(result["final_coverage"]*100, digits=1))%, " *
                    "Directedness=$(round(result["avg_directedness"], digits=3))")
        end
    end

    # Save results
    output_dir = joinpath(@__DIR__, "../../data/experiments")
    mkpath(output_dir)

    using Dates
    output_file = joinpath(output_dir, "exp2_epistemic_exploration_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")).json")

    open(output_file, "w") do f
        JSON.print(f, all_results, 2)
    end

    println("\nResults saved to: $output_file")

    # Print summary
    println("\n=== Summary Statistics ===")
    for controller_type in ["eph", "random"]
        type_results = filter(r -> r["controller_type"] == controller_type, all_results)

        avg_time = mean(r["time_to_unknown"] for r in type_results)
        avg_coverage = mean(r["final_coverage"] for r in type_results) * 100
        avg_direct = mean(r["avg_directedness"] for r in type_results)

        println("[$controller_type Controller]")
        println("  Avg Time to Unknown: $(round(avg_time, digits=1)) steps")
        println("  Avg Coverage: $(round(avg_coverage, digits=1))%")
        println("  Avg Directedness: $(round(avg_direct, digits=3))")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    n_trials = parse(Int, get(ENV, "N_TRIALS", "5"))
    run_experiment(n_trials)
end
