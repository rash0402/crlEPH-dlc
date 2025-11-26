"""
Experiment 1: Lubricant Effect of Haze on Collision Avoidance

Tests whether high haze reduces excessive collision avoidance, allowing agents
to navigate narrow passages more smoothly with higher success rate.

Environment: Narrow corridor (bottleneck) scenario
Variables:
  - Independent: Environmental haze concentration (Low vs High)
  - Dependent: Pass-through success rate, average velocity, wall clearance
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include("../utils/MathUtils.jl")
include("../utils/DataCollector.jl")
include("../utils/ExperimentLogger.jl")
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

"""
Initialize narrow corridor environment with bottleneck
"""
function initialize_corridor_env(;width=400.0, height=200.0, n_agents=5, corridor_width=40.0)
    env = Environment(width, height, grid_size=5)

    # Place agents at the left side
    for i in 1:n_agents
        x = 50.0
        y = height/2 + (i - (n_agents+1)/2) * 15.0
        theta = 0.0  # Facing right

        agent_color = (80, 120, 255)
        agent = Agent(i, x, y, theta=theta, radius=3.0, color=agent_color)
        agent.goal = [width - 50.0, height/2]  # Goal on the right side
        agent.personal_space = 20.0

        push!(env.agents, agent)
    end

    # Create narrow corridor by placing haze (representing walls)
    # Corridor is at the center, spanning from x=150 to x=250
    corridor_center_y = height / 2
    corridor_half_width = corridor_width / 2

    for gx in 1:size(env.haze_grid, 1)
        for gy in 1:size(env.haze_grid, 2)
            x = (gx - 0.5) * env.grid_size
            y = (gy - 0.5) * env.grid_size

            # Wall regions (high haze)
            if 150.0 <= x <= 250.0
                if y < (corridor_center_y - corridor_half_width) || y > (corridor_center_y + corridor_half_width)
                    env.haze_grid[gx, gy] = 0.9  # Wall haze
                end
            end
        end
    end

    return env
end

"""
Run single trial with specified haze level
"""
function run_trial(haze_level::String, trial_id::Int, max_steps::Int=500)
    println("Running Experiment 1 - Trial $trial_id with $haze_level haze...")

    # Initialize environment
    corridor_width = haze_level == "low" ? 60.0 : 40.0  # Narrower for high haze
    env = initialize_corridor_env(corridor_width=corridor_width)

    # Set corridor haze level
    haze_value = haze_level == "low" ? 0.1 : 0.7
    for gx in 1:size(env.haze_grid, 1)
        for gy in 1:size(env.haze_grid, 2)
            x = (gx - 0.5) * env.grid_size
            y = (gy - 0.5) * env.grid_size

            # Corridor area (not walls)
            if 150.0 <= x <= 250.0 && abs(y - env.height/2) <= corridor_width/2
                env.haze_grid[gx, gy] = haze_value
            end
        end
    end

    # Initialize EPH parameters
    config = ConfigLoader.load_config()
    params = ConfigLoader.create_eph_params(config)
    params.enable_env_haze = true
    params.haze_decay_rate = 0.0  # Keep constant haze

    # Initialize predictor
    predictor = SPMPredictor.LinearPredictor(params.prediction_dt)

    # Metrics tracking
    results = Dict(
        "haze_level" => haze_level,
        "trial_id" => trial_id,
        "success" => false,
        "pass_through_time" => 0,
        "avg_velocity" => 0.0,
        "min_clearance" => Inf,
        "collision_count" => 0,
        "trajectory" => []
    )

    # Run simulation
    for step in 1:max_steps
        Simulation.step!(env, params, predictor)

        # Track metrics for each agent
        for agent in env.agents
            # Check if agent passed through corridor
            if agent.position[1] > 250.0 && !get(results, "passed_$(agent.id)", false)
                results["passed_$(agent.id)"] = true
                results["pass_through_time"] = step
            end

            # Track velocity in corridor
            if 150.0 <= agent.position[1] <= 250.0
                push!(get!(results, "velocities", Float64[]), sqrt(sum(agent.velocity.^2)))
            end

            # Track clearance (distance to walls)
            corridor_center_y = env.height / 2
            clearance = min(
                abs(agent.position[2] - (corridor_center_y - corridor_width/2)),
                abs(agent.position[2] - (corridor_center_y + corridor_width/2))
            )
            results["min_clearance"] = min(results["min_clearance"], clearance)

            # Store trajectory
            push!(results["trajectory"], [agent.position[1], agent.position[2]])
        end

        # Check success (all agents passed)
        all_passed = all(agent.position[1] > 250.0 for agent in env.agents)
        if all_passed
            results["success"] = true
            break
        end
    end

    # Compute average velocity
    if !isempty(get(results, "velocities", []))
        results["avg_velocity"] = mean(results["velocities"])
    end

    return results
end

"""
Run full experiment with multiple trials
"""
function run_experiment(n_trials::Int=10)
    println("\n=== Experiment 1: Lubricant Effect ===")
    println("Testing Haze's effect on narrow passage navigation\n")

    all_results = []

    # Run trials for both conditions
    for haze_level in ["low", "high"]
        for trial in 1:n_trials
            result = run_trial(haze_level, trial)
            push!(all_results, result)

            println("  [$haze_level] Trial $trial: Success=$(result["success"]), " *
                    "AvgVel=$(round(result["avg_velocity"], digits=2)), " *
                    "MinClear=$(round(result["min_clearance"], digits=2))")
        end
    end

    # Save results
    output_dir = joinpath(@__DIR__, "../../data/experiments")
    mkpath(output_dir)
    output_file = joinpath(output_dir, "exp1_lubricant_effect_$(Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")).json")

    open(output_file, "w") do f
        JSON.print(f, all_results, 2)
    end

    println("\nResults saved to: $output_file")

    # Print summary statistics
    println("\n=== Summary Statistics ===")
    for haze_level in ["low", "high"]
        level_results = filter(r -> r["haze_level"] == haze_level, all_results)

        success_rate = mean(r["success"] for r in level_results) * 100
        avg_vel = mean(r["avg_velocity"] for r in level_results)
        avg_clearance = mean(r["min_clearance"] for r in level_results)

        println("[$haze_level Haze]")
        println("  Success Rate: $(round(success_rate, digits=1))%")
        println("  Avg Velocity: $(round(avg_vel, digits=2))")
        println("  Avg Min Clearance: $(round(avg_clearance, digits=2))")
    end
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    using Dates
    n_trials = parse(Int, get(ENV, "N_TRIALS", "5"))
    run_experiment(n_trials)
end
