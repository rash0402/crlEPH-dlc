module Simulation

using ..Types
using ..MathUtils
using ..SPM
using ..EPH
using ..SelfHaze
using ..EnvironmentalHaze
using ..FullTensorHaze
using ..DataCollector
using ..SPMPredictor
using LinearAlgebra
using Random
using Statistics

export initialize_simulation, step!

"""
Initialize Sparse Foraging Task environment.

# Scenario
- Multiple agents in toroidal world
- Sparse initial placement (agents far apart)
- No explicit goals (epistemic foraging only)
- FOV: 210° × 100px

# Objective
Test Active Inference hypothesis:
When agents see few neighbors (low Ω), self-haze increases → precision decreases
→ belief entropy increases → epistemic term dominates → exploration emerges

# Parameters
- `width`: World width
- `height`: World height
- `n_agents`: Number of agents
- `grid_size`: Coverage grid cell size (should be ~1.5-2x agent radius)
- `agent_radius`: Agent body radius for visualization and collision
- `personal_space`: Agent personal space radius for avoidance
"""
function initialize_simulation(;width=400.0, height=400.0, n_agents=10,
                                grid_size=5, agent_radius=3.0, personal_space=20.0)
    env = Environment(width, height, grid_size=grid_size)

    # Sparse initial placement: divide world into regions
    # Scaled for variable world size and agent count
    margin = 0.10  # 10% margin from edges (smaller margin = more spread)

    # Generate regions based on number of agents
    if n_agents <= 6
        regions = [
            (x=width * margin, y=height * 0.25),        # Left-top
            (x=width * (1-margin), y=height * 0.25),    # Right-top
            (x=width * margin, y=height * 0.75),        # Left-bottom
            (x=width * (1-margin), y=height * 0.75),    # Right-bottom
            (x=width * 0.5, y=height * 0.15),           # Center-top
            (x=width * 0.5, y=height * 0.85),           # Center-bottom
        ][1:n_agents]
    else
        # For more agents, use grid-based placement with randomized offset
        # to avoid perfect alignment
        cols = ceil(Int, sqrt(n_agents))
        rows = ceil(Int, n_agents / cols)
        regions = []
        for i in 0:(n_agents-1)
            row = div(i, cols)
            col = mod(i, cols)

            # Base grid position
            base_x = width * (margin + (1 - 2*margin) * (col + 0.5) / cols)
            base_y = height * (margin + (1 - 2*margin) * (row + 0.5) / rows)

            # Add randomized offset to break grid pattern (±10% of cell size)
            cell_width = width * (1 - 2*margin) / cols
            cell_height = height * (1 - 2*margin) / rows
            offset_x = (rand() - 0.5) * cell_width * 0.2
            offset_y = (rand() - 0.5) * cell_height * 0.2

            x = base_x + offset_x
            y = base_y + offset_y

            push!(regions, (x=x, y=y))
        end
    end

    # Color assignment: Agent 1 is red, others are blue
    for i in 1:n_agents
        region = regions[i]

        # Use region position directly (no jitter for maximum spacing)
        x = region.x
        y = region.y

        # Random initial orientation
        theta = rand() * 2π - π

        # Agent 1 is red (for tracking), others are blue
        if i == 1
            agent_color = (255, 80, 80)  # Red
        else
            agent_color = (80, 120, 255)  # Blue
        end

        agent = Agent(i, x, y, theta=theta, radius=agent_radius, color=agent_color)

        # No explicit goals (epistemic foraging only)
        agent.goal = nothing

        # Set personal space from config
        agent.personal_space = personal_space

        push!(env.agents, agent)
    end

    return env
end

"""
    step!(env::Environment, params::EPHParams, predictor::SPMPredictor.Predictor, external_haze_tensor=nothing)

Execute one simulation timestep with Active Inference-based EPH control.

# Workflow
1. Perception: Compute SPM for each agent
2. Inference: Compute self-haze and belief entropy (optionally overridden by external_haze_tensor)
3. Action Selection: Minimize Expected Free Energy G(a)
4. Physics: Update positions and orientations
5. Tracking: Update coverage map and detect information gain events

# Arguments
- `external_haze_tensor`: Optional 6x6 matrix to override self-computed precision for all agents
"""
function step!(env::Environment, params::EPHParams, predictor::SPMPredictor.Predictor, external_haze_tensor=nothing)
    spm_params = SPM.SPMParams(d_max=params.fov_range, fov_angle=params.fov_angle)

    # --- 1. Perception & Action Selection ---
    for agent in env.agents
        # Store previous SPM for prediction-based surprise
        agent.previous_spm = agent.current_spm
        
        # Compute SPM (Saliency Polar Map)
        spm = SPM.compute_spm(agent, env, spm_params)

        # Store SPM for visualization/debugging
        agent.current_spm = spm

        # Data Collection (Phase 2 & 5)
        if params.collect_data && agent.previous_spm !== nothing && agent.last_action !== nothing
            # Record transition with FOV occupancy for importance weighting
            visible_count = length(agent.visible_agents)
            DataCollector.collect_transition(agent.id, agent.previous_spm, agent.last_action, 
                                            agent.current_spm, visible_count)
            
            # Auto-save every N samples to prevent memory overflow
            # Note: When collecting single-agent data, this threshold should be high
            # to allow long continuous sequences
            total_samples = sum(length(b) for b in values(DataCollector.agent_buffers); init=0)
            auto_save_threshold = 50000  # High threshold for single-agent collection
            if total_samples >= auto_save_threshold
                println("\n[Auto-save] Reached $total_samples samples, saving...")
                DataCollector.save_data("spm_sequences")
            end
        end

        # Update Predictor State (Phase 3)
        # We use previous_spm and last_action because these correspond to the transition
        # that just happened (or rather, the decision made at t resulted in state update).
        # Wait, GRU needs (s_t, a_t) to update state h_t -> h_{t+1}.
        # agent.previous_spm is s_t. agent.last_action is a_t.
        if agent.previous_spm !== nothing && agent.last_action !== nothing
            SPMPredictor.update_state!(predictor, agent, agent.previous_spm, agent.last_action)
        end
        
        # Compute self-haze and precision (Phase 1/2/3)
        if params.enable_full_tensor
            # Phase 3: Full 3D Tensor Haze with per-channel control
            # Create FullTensorHazeParams from EPHParams
            fth_params = FullTensorHaze.FullTensorHazeParams(
                w_occupancy = params.channel_weights[1],
                w_radial_vel = params.channel_weights[2],
                w_tangential_vel = params.channel_weights[3],
                Ω_threshold_occ = params.Ω_threshold_occ,
                Ω_threshold_rad = params.Ω_threshold_rad,
                Ω_threshold_tan = params.Ω_threshold_tan,
                α_occ = params.α_occ,
                α_rad = params.α_rad,
                α_tan = params.α_tan,
                h_max_occ = params.h_max_occ,
                h_max_rad = params.h_max_rad,
                h_max_tan = params.h_max_tan,
                γ = params.γ
            )

            # Compute 3D haze tensor H(c, r, θ)
            haze_tensor = FullTensorHaze.compute_full_tensor_haze(spm, fth_params)

            # Apply channel mask for selective attention
            masked_haze = FullTensorHaze.apply_channel_mask(haze_tensor, params.channel_mask)

            # Compute per-channel precision tensor Π(c, r, θ)
            precision_tensor = FullTensorHaze.compute_channel_precision(spm, masked_haze, fth_params)

            # Collapse 3D precision tensor to 2D using weighted average
            # Π(r, θ) = Σ_c w_c * Π(c, r, θ)
            Nc, Nr, Nθ = size(precision_tensor)
            Π = zeros(Float64, Nr, Nθ)
            for c in 1:Nc
                Π .+= params.channel_weights[c] .* precision_tensor[c, :, :]
            end
            # Normalize by sum of weights
            Π ./= sum(params.channel_weights)

            # Store scalar haze for backward compatibility (weighted mean)
            agent.self_haze = sum(params.channel_weights .* [mean(masked_haze[c, :, :]) for c in 1:Nc]) / sum(params.channel_weights)

        elseif params.enable_env_haze
            # Phase 2: Spatial haze (h_matrix) + Environmental haze
            h_self_matrix = SelfHaze.compute_self_haze_matrix(spm, params)

            # Sample environmental haze at SPM locations
            Nr, Nθ = size(spm, 2), size(spm, 3)
            h_env_matrix = EnvironmentalHaze.sample_environmental_haze(agent, env, Nr, Nθ, params.fov_range)

            # Compose total haze: H_total = max(H_self, H_env)
            h_total_matrix = EnvironmentalHaze.compose_haze(h_self_matrix, h_env_matrix)

            # Store scalar haze for backward compatibility (mean of matrix)
            agent.self_haze = mean(h_total_matrix)

            # Compute precision matrix with spatial haze
            Π = SelfHaze.compute_precision_matrix(spm, h_total_matrix, params)
        else
            # Phase 1: Scalar haze (backward compatible)
            agent.self_haze = SelfHaze.compute_self_haze(spm, params)
            Π = SelfHaze.compute_precision_matrix(spm, agent.self_haze, params)
        end

        # Override with external haze tensor if provided
        if external_haze_tensor !== nothing
            # External haze tensor is a 6x6 matrix specifying precision directly
            # Convert haze values (0.0-1.0) to precision (1.0-0.0): higher haze = lower precision
            Π = params.Π_max .* (1.0 .- external_haze_tensor)
        end

        # Track visible agents (for analysis)
        agent.visible_agents = _get_visible_agent_ids(agent, env, params)

        # Store precision matrix for visualization
        agent.current_precision = Π

        # Preferred velocity (no goals in sparse foraging)
        pref_vel = nothing
        if agent.goal !== nothing
            dx, dy, dist = toroidal_distance(agent.position, agent.goal, env.width, env.height)
            if dist > 0
                pref_vel = [dx / dist * params.max_speed, dy / dist * params.max_speed]
            end
        end

        # Decide action by minimizing Expected Free Energy
        controller = EPH.GradientEPHController(params, predictor)
        action = EPH.decide_action(controller, agent, spm, env, pref_vel)
        
        # Store action for data collection in next step
        agent.last_action = copy(action)
        agent.velocity = action
    end

    # --- 2. Physics Update ---
    dt = env.dt
    for agent in env.agents
        # Update position
        agent.position += agent.velocity * dt

        # Toroidal wrap-around
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)

        # Update orientation (heading direction)
        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end

    # --- 3. Environmental Haze Update (Phase 2) ---
    if params.enable_env_haze
        # Deposit haze trails at agent positions (stigmergy)
        for agent in env.agents
            EnvironmentalHaze.deposit_haze_trail!(env, agent, params.haze_deposit_type, params.haze_deposit_amount)
        end

        # Global haze decay (temporal forgetting)
        EnvironmentalHaze.decay_haze_grid!(env, params.haze_decay_rate)
    end

    # --- 4. Coverage Map Update ---
    _update_coverage_map!(env, params)

    # --- 4. Frame Counter ---
    env.frame_count += 1
end

"""
    _get_visible_agent_ids(agent, env, params) -> Vector{Int}

Get IDs of agents currently within FOV.
Used for tracking visible neighbors and computing occupancy statistics.
"""
function _get_visible_agent_ids(agent::Agent, env::Environment, params::EPHParams)::Vector{Int}
    visible_ids = Int[]

    for other in env.agents
        if other.id == agent.id
            continue
        end

        # Compute toroidal distance
        dx, dy, dist = toroidal_distance(agent.position, other.position, env.width, env.height)

        # Check if within range
        if dist > params.fov_range
            continue
        end

        # Check if within FOV angle
        angle_to_other = atan(dy, dx)
        relative_angle = mod(angle_to_other - agent.orientation + π, 2π) - π

        if abs(relative_angle) <= params.fov_angle / 2.0
            push!(visible_ids, other.id)
        end
    end

    return visible_ids
end

"""
    _update_coverage_map!(env, params)

Update coverage map based on current agent positions.
Marks grid cells as covered if an agent is within detection range.
"""
function _update_coverage_map!(env::Environment, params::EPHParams)
    grid_w = size(env.coverage_map, 1)
    grid_h = size(env.coverage_map, 2)

    for agent in env.agents
        # Compute grid coordinates
        gx = clamp(floor(Int, agent.position[1] / env.grid_size) + 1, 1, grid_w)
        gy = clamp(floor(Int, agent.position[2] / env.grid_size) + 1, 1, grid_h)

        # Increment visit count (only agent's current cell, not adjacent cells)
        env.coverage_map[gx, gy] += 1
    end
end

"""
    compute_coverage(env::Environment) -> Float64

Compute the fraction of the environment visited by agents (cells with visit_count > 0).
"""
function compute_coverage(env::Environment)::Float64
    visited_cells = count(x -> x > 0, env.coverage_map)
    return visited_cells / length(env.coverage_map)
end

end
