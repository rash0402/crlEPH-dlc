module ExperimentLogger

using Dates
using Statistics
using JLD2
using FileIO

export Logger, log_step, log_agent_metrics, log_system_metrics, save_log, analyze_results,
       log_health_metrics, log_prediction_metrics, log_gradient_metrics, log_selfhaze_metrics

"""
    Logger

Comprehensive experiment logger for tracking agent behavior and system metrics.
Includes diagnostics for system health, GRU prediction, gradient-based control, and self-haze dynamics.
"""
mutable struct Logger
    log_dir::String
    experiment_name::String
    start_time::DateTime

    # Step-by-step data
    steps::Vector{Int}
    timestamps::Vector{Float64}

    # Agent-level metrics (basic)
    agent_positions::Vector{Vector{Tuple{Float64, Float64}}}
    agent_velocities::Vector{Vector{Float64}}
    agent_efe_values::Vector{Vector{Float64}}
    agent_visible_counts::Vector{Vector{Int}}
    agent_haze_exposure::Vector{Vector{Float64}}

    # System-level metrics
    coverage_history::Vector{Float64}
    total_haze::Vector{Float64}
    avg_separation::Vector{Float64}
    collision_count::Vector{Int}

    # === Phase 1: System Health Diagnostics ===
    # Physical consistency
    velocity_magnitudes::Vector{Vector{Float64}}           # Speed per agent
    acceleration_magnitudes::Vector{Vector{Float64}}       # Acceleration per agent
    toroidal_wrap_events::Vector{Int}                      # Boundary crossings per step

    # Numerical stability
    nan_inf_detected::Vector{Bool}                         # NaN/Inf detection per step
    spm_value_ranges::Vector{Tuple{Float64, Float64}}      # (min, max) SPM values per step

    # === Phase 2: GRU Prediction Performance ===
    prediction_errors::Vector{Vector{Float64}}             # MSE per agent (already exists)
    prediction_errors_occupancy::Vector{Vector{Float64}}   # Occupancy channel error
    prediction_errors_velocity::Vector{Vector{Float64}}    # Velocity channel error
    hidden_state_norms::Vector{Vector{Float64}}            # ||h_t|| per agent (already exists)
    hidden_state_saturation::Vector{Vector{Float64}}       # Saturation rate (|h| > 0.9)

    # === Phase 3: Gradient-Driven System Diagnostics ===
    agent_gradient_norms::Vector{Vector{Float64}}          # ||∇G|| per agent
    action_continuity::Vector{Vector{Float64}}             # ||a_t - a_{t-1}|| per agent
    efe_improvement_rate::Vector{Vector{Float64}}          # (G_before - G_after) / G_before

    # === Phase 4: Self-Haze Dynamics ===
    agent_self_haze_values::Vector{Vector{Float64}}        # h_self per agent
    agent_occupancy_measures::Vector{Vector{Float64}}      # Ω(SPM) per agent
    self_haze_transitions::Vector{Vector{Int}}             # Transition count: isolated(0)↔grouped(1)

    # Correlation analysis
    self_haze_vs_velocity::Vector{Vector{Tuple{Float64, Float64}}}  # (h_self, speed)

    # === Phase 5: Active Inference Belief Entropy ===
    agent_belief_entropy::Vector{Vector{Float64}}          # H[q(s|a)] per agent
end

function Logger(experiment_name::String="experiment")
    log_dir = joinpath("data", "logs")
    mkpath(log_dir)

    Logger(
        log_dir,
        experiment_name,
        now(),
        # Step-by-step data
        Int[],
        Float64[],
        # Agent-level metrics (basic)
        Vector{Tuple{Float64, Float64}}[],
        Vector{Float64}[],
        Vector{Float64}[],
        Vector{Int}[],
        Vector{Float64}[],
        # System-level metrics
        Float64[],
        Float64[],
        Float64[],
        Int[],
        # Phase 1: System Health
        Vector{Float64}[],       # velocity_magnitudes
        Vector{Float64}[],       # acceleration_magnitudes
        Int[],                   # toroidal_wrap_events
        Bool[],                  # nan_inf_detected
        Tuple{Float64, Float64}[],  # spm_value_ranges
        # Phase 2: GRU Prediction
        Vector{Float64}[],       # prediction_errors
        Vector{Float64}[],       # prediction_errors_occupancy
        Vector{Float64}[],       # prediction_errors_velocity
        Vector{Float64}[],       # hidden_state_norms
        Vector{Float64}[],       # hidden_state_saturation
        # Phase 3: Gradient-Driven System
        Vector{Float64}[],       # agent_gradient_norms
        Vector{Float64}[],       # action_continuity
        Vector{Float64}[],       # efe_improvement_rate
        # Phase 4: Self-Haze Dynamics
        Vector{Float64}[],       # agent_self_haze_values
        Vector{Float64}[],       # agent_occupancy_measures
        Vector{Int}[],           # self_haze_transitions
        Vector{Tuple{Float64, Float64}}[],  # self_haze_vs_velocity
        # Phase 5: Belief Entropy
        Vector{Float64}[]        # agent_belief_entropy
    )
end

"""
    log_step(logger, step, time, agents, env)

Log data for a single simulation step.
"""
function log_step(logger::Logger, step::Int, time::Float64, agents, env)
    push!(logger.steps, step)
    push!(logger.timestamps, time)
    
    # Agent positions and velocities
    positions = [(a.position[1], a.position[2]) for a in agents]
    velocities = [sqrt(a.velocity[1]^2 + a.velocity[2]^2) for a in agents]
    visible_counts = [length(a.visible_agents) for a in agents]
    belief_entropies = [a.belief_entropy for a in agents]

    push!(logger.agent_positions, positions)
    push!(logger.agent_velocities, velocities)
    push!(logger.agent_visible_counts, visible_counts)
    push!(logger.agent_belief_entropy, belief_entropies)
    
    # Haze exposure (sample haze at agent positions)
    haze_values = Float64[]
    for a in agents
        x_idx = Int(clamp(round(a.position[1] / env.width * size(env.haze_grid, 1)), 1, size(env.haze_grid, 1)))
        y_idx = Int(clamp(round(a.position[2] / env.height * size(env.haze_grid, 2)), 1, size(env.haze_grid, 2)))
        push!(haze_values, env.haze_grid[x_idx, y_idx])
    end
    push!(logger.agent_haze_exposure, haze_values)
end

"""
    log_agent_metrics(logger, agents, efe_values)

Log agent-specific metrics like EFE values.
"""
function log_agent_metrics(logger::Logger, efe_values::Vector{Float64})
    push!(logger.agent_efe_values, efe_values)
end

"""
    log_system_metrics(logger, coverage, total_haze, avg_sep, collisions)

Log system-wide metrics.
"""
function log_system_metrics(logger::Logger, coverage::Float64, total_haze::Float64, 
                            avg_sep::Float64, collisions::Int)
    push!(logger.coverage_history, coverage)
    push!(logger.total_haze, total_haze)
    push!(logger.avg_separation, avg_sep)
    push!(logger.collision_count, collisions)
end

"""
    log_predictor_metrics(logger, pred_errors, hidden_norms)

Log predictor-specific metrics.
"""
function log_predictor_metrics(logger::Logger, pred_errors::Vector{Float64},
                               hidden_norms::Vector{Float64})
    push!(logger.prediction_errors, pred_errors)
    push!(logger.hidden_state_norms, hidden_norms)
end

"""
    log_health_metrics(logger, agents, env, prev_positions, prev_velocities)

Log Phase 1 system health diagnostics.
"""
function log_health_metrics(logger::Logger, agents, env,
                            prev_positions::Union{Vector{Tuple{Float64, Float64}}, Nothing},
                            prev_velocities::Union{Vector{Float64}, Nothing})
    # Velocity magnitudes
    vel_mags = [sqrt(a.velocity[1]^2 + a.velocity[2]^2) for a in agents]
    push!(logger.velocity_magnitudes, vel_mags)

    # Acceleration magnitudes (if previous velocities available)
    if prev_velocities !== nothing
        accel_mags = [abs(vel_mags[i] - prev_velocities[i]) / env.dt for i in 1:length(agents)]
        push!(logger.acceleration_magnitudes, accel_mags)
    else
        push!(logger.acceleration_magnitudes, zeros(Float64, length(agents)))
    end

    # Toroidal wrap events (count boundary crossings)
    wrap_count = 0
    if prev_positions !== nothing
        for (i, a) in enumerate(agents)
            prev_pos = prev_positions[i]
            dx = abs(a.position[1] - prev_pos[1])
            dy = abs(a.position[2] - prev_pos[2])
            # Large jumps indicate wrapping
            if dx > env.width / 2 || dy > env.height / 2
                wrap_count += 1
            end
        end
    end
    push!(logger.toroidal_wrap_events, wrap_count)

    # NaN/Inf detection
    has_nan_inf = any(a -> any(isnan, a.position) || any(isinf, a.position) ||
                            any(isnan, a.velocity) || any(isinf, a.velocity), agents)
    push!(logger.nan_inf_detected, has_nan_inf)

    # SPM value ranges
    spm_min, spm_max = Inf, -Inf
    for a in agents
        if a.current_spm !== nothing
            spm_min = min(spm_min, minimum(a.current_spm))
            spm_max = max(spm_max, maximum(a.current_spm))
        end
    end
    push!(logger.spm_value_ranges, (spm_min == Inf ? 0.0 : spm_min,
                                    spm_max == -Inf ? 0.0 : spm_max))
end

"""
    log_prediction_metrics(logger, agents, predictor, env, spm_params)

Log Phase 2 GRU prediction performance metrics.
"""
function log_prediction_metrics(logger::Logger, agents, predictor, env, spm_params)
    pred_errors = Float64[]
    pred_errors_occ = Float64[]
    pred_errors_vel = Float64[]
    hidden_norms = Float64[]
    hidden_sat = Float64[]

    for a in agents
        if a.current_spm !== nothing && a.previous_spm !== nothing && a.last_action !== nothing
            # Compute prediction using predictor
            spm_pred = try
                # Use SPMPredictor module if available
                if isdefined(Main, :SPMPredictor)
                    Main.SPMPredictor.predict_spm(predictor, a, a.last_action, env, spm_params)
                else
                    nothing
                end
            catch
                nothing
            end

            if spm_pred !== nothing
                # Total prediction error (MSE)
                mse = mean((a.current_spm .- spm_pred).^2)
                push!(pred_errors, mse)

                # Occupancy channel error
                mse_occ = mean((a.current_spm[1, :, :] .- spm_pred[1, :, :]).^2)
                push!(pred_errors_occ, mse_occ)

                # Velocity channel error
                mse_vel = mean((a.current_spm[2:3, :, :] .- spm_pred[2:3, :, :]).^2)
                push!(pred_errors_vel, mse_vel)
            else
                push!(pred_errors, 0.0)
                push!(pred_errors_occ, 0.0)
                push!(pred_errors_vel, 0.0)
            end
        else
            push!(pred_errors, 0.0)
            push!(pred_errors_occ, 0.0)
            push!(pred_errors_vel, 0.0)
        end

        # Hidden state metrics
        if a.hidden_state !== nothing
            h_norm = sqrt(sum(a.hidden_state.^2))
            push!(hidden_norms, h_norm)

            # Saturation: fraction of hidden units with |h| > 0.9
            saturation = sum(abs.(a.hidden_state) .> 0.9) / length(a.hidden_state)
            push!(hidden_sat, saturation)
        else
            push!(hidden_norms, 0.0)
            push!(hidden_sat, 0.0)
        end
    end

    push!(logger.prediction_errors, pred_errors)
    push!(logger.prediction_errors_occupancy, pred_errors_occ)
    push!(logger.prediction_errors_velocity, pred_errors_vel)
    push!(logger.hidden_state_norms, hidden_norms)
    push!(logger.hidden_state_saturation, hidden_sat)
end

"""
    log_gradient_metrics(logger, agents, prev_actions, efe_before, efe_after)

Log Phase 3 gradient-driven system diagnostics.
"""
function log_gradient_metrics(logger::Logger, agents,
                              prev_actions::Union{Vector{Vector{Float64}}, Nothing},
                              efe_before::Union{Vector{Float64}, Nothing},
                              efe_after::Union{Vector{Float64}, Nothing})
    grad_norms = Float64[]
    action_cont = Float64[]
    efe_improve = Float64[]

    for (i, a) in enumerate(agents)
        # Gradient norm
        if a.current_gradient !== nothing
            push!(grad_norms, sqrt(sum(a.current_gradient.^2)))
        else
            push!(grad_norms, 0.0)
        end

        # Action continuity
        if prev_actions !== nothing && i <= length(prev_actions)
            action_diff = sqrt(sum((a.velocity .- prev_actions[i]).^2))
            push!(action_cont, action_diff)
        else
            push!(action_cont, 0.0)
        end

        # EFE improvement rate
        if efe_before !== nothing && efe_after !== nothing && i <= length(efe_before)
            if efe_before[i] > 1e-6
                improvement = (efe_before[i] - efe_after[i]) / efe_before[i]
                push!(efe_improve, improvement)
            else
                push!(efe_improve, 0.0)
            end
        else
            push!(efe_improve, 0.0)
        end
    end

    push!(logger.agent_gradient_norms, grad_norms)
    push!(logger.action_continuity, action_cont)
    push!(logger.efe_improvement_rate, efe_improve)
end

"""
    log_selfhaze_metrics(logger, agents, prev_self_haze)

Log Phase 4 self-haze dynamics and correlation metrics.
"""
function log_selfhaze_metrics(logger::Logger, agents,
                              prev_self_haze::Union{Vector{Float64}, Nothing})
    self_haze_vals = Float64[]
    occupancy_measures = Float64[]
    transitions = Int[]
    haze_vel_pairs = Tuple{Float64, Float64}[]

    for (i, a) in enumerate(agents)
        # Self-haze value
        push!(self_haze_vals, a.self_haze)

        # Occupancy measure (mean occupancy in SPM)
        if a.current_spm !== nothing
            mean_occ = mean(a.current_spm[1, :, :])
            push!(occupancy_measures, mean_occ)
        else
            push!(occupancy_measures, 0.0)
        end

        # Transition detection (threshold at 0.5)
        if prev_self_haze !== nothing && i <= length(prev_self_haze)
            was_isolated = prev_self_haze[i] > 0.5
            is_isolated = a.self_haze > 0.5
            transition = (was_isolated != is_isolated) ? 1 : 0
            push!(transitions, transition)
        else
            push!(transitions, 0)
        end

        # Correlation: self-haze vs velocity
        speed = sqrt(a.velocity[1]^2 + a.velocity[2]^2)
        push!(haze_vel_pairs, (a.self_haze, speed))
    end

    push!(logger.agent_self_haze_values, self_haze_vals)
    push!(logger.agent_occupancy_measures, occupancy_measures)
    push!(logger.self_haze_transitions, transitions)
    push!(logger.self_haze_vs_velocity, haze_vel_pairs)
end

"""
    save_log(logger)

Save logged data to file.
"""
function save_log(logger::Logger)
    timestamp = Dates.format(logger.start_time, "yyyy-mm-dd_HH-MM-SS")
    filename = joinpath(logger.log_dir, "$(logger.experiment_name)_$(timestamp).jld2")

    save(filename, Dict(
        # Metadata
        "experiment_name" => logger.experiment_name,
        "start_time" => logger.start_time,
        "steps" => logger.steps,
        "timestamps" => logger.timestamps,
        # Basic agent metrics
        "agent_positions" => logger.agent_positions,
        "agent_velocities" => logger.agent_velocities,
        "agent_efe_values" => logger.agent_efe_values,
        "agent_visible_counts" => logger.agent_visible_counts,
        "agent_haze_exposure" => logger.agent_haze_exposure,
        # System metrics
        "coverage_history" => logger.coverage_history,
        "total_haze" => logger.total_haze,
        "avg_separation" => logger.avg_separation,
        "collision_count" => logger.collision_count,
        # Phase 1: System Health
        "velocity_magnitudes" => logger.velocity_magnitudes,
        "acceleration_magnitudes" => logger.acceleration_magnitudes,
        "toroidal_wrap_events" => logger.toroidal_wrap_events,
        "nan_inf_detected" => logger.nan_inf_detected,
        "spm_value_ranges" => logger.spm_value_ranges,
        # Phase 2: GRU Prediction
        "prediction_errors" => logger.prediction_errors,
        "prediction_errors_occupancy" => logger.prediction_errors_occupancy,
        "prediction_errors_velocity" => logger.prediction_errors_velocity,
        "hidden_state_norms" => logger.hidden_state_norms,
        "hidden_state_saturation" => logger.hidden_state_saturation,
        # Phase 3: Gradient-Driven System
        "agent_gradient_norms" => logger.agent_gradient_norms,
        "action_continuity" => logger.action_continuity,
        "efe_improvement_rate" => logger.efe_improvement_rate,
        # Phase 4: Self-Haze Dynamics
        "agent_self_haze_values" => logger.agent_self_haze_values,
        "agent_occupancy_measures" => logger.agent_occupancy_measures,
        "self_haze_transitions" => logger.self_haze_transitions,
        "self_haze_vs_velocity" => logger.self_haze_vs_velocity,
        # Phase 5: Active Inference Belief Entropy
        "agent_belief_entropy" => logger.agent_belief_entropy
    ))

    println("✓ Comprehensive experiment log saved to: $filename")
    return filename
end

"""
    analyze_results(log_file)

Analyze and print summary statistics from a log file.
"""
function analyze_results(log_file::String)
    data = load(log_file)
    
    println("\n" * "="^60)
    println("Experiment Analysis: $(data["experiment_name"])")
    println("="^60)
    
    println("\n[Simulation Overview]")
    println("  Start time: $(data["start_time"])")
    println("  Total steps: $(length(data["steps"]))")
    println("  Duration: $(round(data["timestamps"][end], digits=2))s")
    
    println("\n[Coverage Metrics]")
    coverage = data["coverage_history"]
    println("  Initial coverage: $(round(coverage[1], digits=2))%")
    println("  Final coverage: $(round(coverage[end], digits=2))%")
    println("  Average coverage: $(round(mean(coverage), digits=2))%")
    println("  Time to 90%: $(findfirst(c -> c >= 90, coverage)) steps")
    
    println("\n[Agent Behavior]")
    velocities = vcat(data["agent_velocities"]...)
    println("  Average velocity: $(round(mean(velocities), digits=2)) units/s")
    println("  Max velocity: $(round(maximum(velocities), digits=2)) units/s")
    
    visible_counts = vcat(data["agent_visible_counts"]...)
    println("  Average visible agents: $(round(mean(visible_counts), digits=2))")
    println("  Max visible agents: $(maximum(visible_counts))")
    println("  % time alone: $(round(100 * sum(visible_counts .== 0) / length(visible_counts), digits=2))%")
    
    println("\n[Haze Dynamics]")
    total_haze = data["total_haze"]
    println("  Initial total haze: $(round(total_haze[1], digits=2))")
    println("  Final total haze: $(round(total_haze[end], digits=2))")
    println("  Peak haze: $(round(maximum(total_haze), digits=2))")
    
    haze_exposure = vcat(data["agent_haze_exposure"]...)
    println("  Average agent haze exposure: $(round(mean(haze_exposure), digits=4))")
    println("  Max agent haze exposure: $(round(maximum(haze_exposure), digits=4))")
    
    println("\n[Spatial Distribution]")
    avg_sep = data["avg_separation"]
    println("  Average separation: $(round(mean(avg_sep), digits=2)) units")
    println("  Min separation: $(round(minimum(avg_sep), digits=2)) units")
    
    if !isempty(data["agent_efe_values"])
        println("\n[Expected Free Energy]")
        efe_values = vcat(data["agent_efe_values"]...)
        println("  Average EFE: $(round(mean(efe_values), digits=4))")
        println("  Min EFE: $(round(minimum(efe_values), digits=4))")
        println("  Max EFE: $(round(maximum(efe_values), digits=4))")
    end
    
    if !isempty(data["prediction_errors"])
        println("\n[Predictor Performance]")
        pred_errors = vcat(data["prediction_errors"]...)
        println("  Average prediction error: $(round(mean(pred_errors), digits=4))")
        println("  Prediction error std: $(round(std(pred_errors), digits=4))")
    end
    
    println("\n" * "="^60)
end

end
