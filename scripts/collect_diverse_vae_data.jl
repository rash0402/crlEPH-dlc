#!/usr/bin/env julia

"""
Enhanced Training Data Collection Script for Action-Conditioned VAE (EPH v5.5)
Supports multiple density levels and diverse scenarios for robust VAE training.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using LinearAlgebra
using HDF5
using Random

# Load modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/prediction.jl")
include("../src/controller.jl")

using .Config
using .SPM
using .Dynamics
using .Controller

"""
Density configuration for data collection
"""
struct DensityConfig
    name::String
    n_agents_per_group::Int
    description::String
end

# Define density levels
const DENSITY_CONFIGS = [
    DensityConfig("low", 5, "Low density (5 agents/group)"),
    DensityConfig("medium", 10, "Medium density (10 agents/group)"),
    DensityConfig("high", 15, "High density (15 agents/group)")
]

"""
Collect training data for Action-Conditioned VAE with diverse scenarios.
Returns arrays of (spm_current, action, spm_next) tuples.
"""
function collect_diverse_training_data(;
    num_episodes_per_density::Int=30,
    steps_per_episode::Int=200,
    exploration_rate::Float64=0.3,
    exploration_noise::Float64=0.5,
    seed_start::Int=1,
    density_configs::Vector{DensityConfig}=DENSITY_CONFIGS
)
    # Storage for training data
    spm_current_list = Vector{Array{Float32, 3}}()
    action_list = Vector{Vector{Float32}}()
    spm_next_list = Vector{Array{Float32, 3}}()
    metadata_list = Vector{Dict{String, Any}}()
    
    println("🎲 Collecting Diverse Action-Conditioned VAE training data...")
    println("   Density levels: $(length(density_configs))")
    println("   Episodes per density: $num_episodes_per_density")
    println("   Steps per episode: $steps_per_episode")
    println("   Exploration rate: $exploration_rate")
    println("   Exploration noise: $exploration_noise")
    println()
    
    episode_counter = 0
    
    for density_config in density_configs
        println("📊 Collecting data for: $(density_config.description)")
        
        for episode in 1:num_episodes_per_density
            episode_counter += 1
            
            # Initialize parameters with current density
            world_params = WorldParams(max_steps=steps_per_episode)
            agent_params = AgentParams(n_agents_per_group=density_config.n_agents_per_group)
            spm_params = SPMParams()
            control_params = ControlParams(
                exploration_rate=exploration_rate,
                exploration_noise=exploration_noise
            )
            spm_config = init_spm(spm_params)
            
            # Initialize agents with different seeds
            agents = init_agents(agent_params, world_params, seed=seed_start + episode_counter)
            obstacles = init_obstacles(world_params)
            
            # Select a random agent to track
            tracked_agent_id = rand(1:length(agents))
            agent = agents[tracked_agent_id]
            
            # Store previous SPM for next-step prediction
            prev_spm = nothing
            prev_action = nothing
            
            for step in 1:steps_per_episode
                # Get other agents (for SPM generation)
                other_agents = [a for a in agents if a.id != agent.id]
                
                # Compute relative positions/velocities
                rel_pos = [relative_position(agent.pos, a.pos, world_params) for a in other_agents]
                
                # Transform to ego-centric frame
                heading = atan(agent.vel[2], agent.vel[1])
                c = cos(-heading)
                s = sin(-heading)
                rotation = [c -s; s c]
                
                rel_pos_ego = [rotation * p for p in rel_pos]
                rel_vel = [a.vel - agent.vel for a in other_agents]
                
                # Generate current SPM
                spm = generate_spm_3ch(spm_config, rel_pos_ego, rel_vel, agent_params.r_agent, agent.precision)
                
                # Compute action
                action = compute_action(agent, spm, control_params, agent_params)
                
                # Apply exploration
                if rand() < exploration_rate
                    # Random action
                    action = (rand(2) .* 2 .- 1) .* agent_params.u_max
                elseif exploration_noise > 0
                    # Add noise
                    noise = randn(2) .* exploration_noise .* agent_params.u_max
                    action = action .+ noise
                end
                action = clamp.(action, -agent_params.u_max, agent_params.u_max)
                
                # Store training tuple (from previous step)
                if prev_spm !== nothing
                    push!(spm_current_list, Float32.(prev_spm))
                    push!(action_list, Float32.(prev_action))
                    push!(spm_next_list, Float32.(spm))
                    push!(metadata_list, Dict(
                        "density" => density_config.name,
                        "n_agents" => length(agents),
                        "episode" => episode_counter,
                        "step" => step
                    ))
                end
                
                # Update previous
                prev_spm = copy(spm)
                prev_action = copy(action)
                
                # Step all agents
                for a in agents
                    if a.id == agent.id
                        step!(a, action, agent_params, world_params, obstacles, agents)
                    else
                        # Other agents use their own FEP control
                        other_rel_pos = [relative_position(a.pos, o.pos, world_params) for o in agents if o.id != a.id]
                        other_heading = atan(a.vel[2], a.vel[1])
                        oc = cos(-other_heading)
                        os = sin(-other_heading)
                        other_rotation = [oc -os; os oc]
                        other_rel_pos_ego = [other_rotation * p for p in other_rel_pos]
                        other_rel_vel = [o.vel - a.vel for o in agents if o.id != a.id]
                        
                        other_spm = generate_spm_3ch(spm_config, other_rel_pos_ego, other_rel_vel, agent_params.r_agent, a.precision)
                        other_action = compute_action(a, other_spm, control_params, agent_params)
                        step!(a, other_action, agent_params, world_params, obstacles, agents)
                    end
                end
            end
            
            if episode % 10 == 0
                @printf("  Episode %3d / %d complete (samples: %d)\\n", episode, num_episodes_per_density, length(spm_current_list))
            end
        end
        
        println("  ✓ $(density_config.name) density complete\\n")
    end
    
    println("✅ Data collection complete!")
    println("   Total samples: $(length(spm_current_list))")
    println("   Density breakdown:")
    for config in density_configs
        count = sum(m["density"] == config.name for m in metadata_list)
        @printf("     - %s: %d samples\\n", config.name, count)
    end
    
    return spm_current_list, action_list, spm_next_list, metadata_list
end

"""
Split data into train/validation/test sets.
"""
function split_dataset(
    spm_current::Vector{Array{Float32, 3}},
    actions::Vector{Vector{Float32}},
    spm_next::Vector{Array{Float32, 3}},
    metadata::Vector{Dict{String, Any}};
    train_ratio::Float64=0.7,
    val_ratio::Float64=0.15,
    test_ratio::Float64=0.15,
    seed::Int=42
)
    @assert train_ratio + val_ratio + test_ratio ≈ 1.0 "Ratios must sum to 1.0"
    
    n_samples = length(spm_current)
    Random.seed!(seed)
    indices = randperm(n_samples)
    
    n_train = Int(floor(n_samples * train_ratio))
    n_val = Int(floor(n_samples * val_ratio))
    
    train_idx = indices[1:n_train]
    val_idx = indices[n_train+1:n_train+n_val]
    test_idx = indices[n_train+n_val+1:end]
    
    return (
        train = (
            spm_current = spm_current[train_idx],
            actions = actions[train_idx],
            spm_next = spm_next[train_idx],
            metadata = metadata[train_idx]
        ),
        val = (
            spm_current = spm_current[val_idx],
            actions = actions[val_idx],
            spm_next = spm_next[val_idx],
            metadata = metadata[val_idx]
        ),
        test = (
            spm_current = spm_current[test_idx],
            actions = actions[test_idx],
            spm_next = spm_next[test_idx],
            metadata = metadata[test_idx]
        )
    )
end

"""
Save collected data to HDF5 file with train/val/test splits.
"""
function save_training_data_with_splits(
    splits::NamedTuple;
    output_dir::String="data/vae_training"
)
    mkpath(output_dir)
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    
    for (split_name, split_data) in pairs(splits)
        n_samples = length(split_data.spm_current)
        
        # Stack arrays
        spm_current = zeros(Float32, 16, 16, 3, n_samples)
        spm_next = zeros(Float32, 16, 16, 3, n_samples)
        actions = zeros(Float32, 2, n_samples)
        
        for i in 1:n_samples
            spm_current[:, :, :, i] = split_data.spm_current[i]
            spm_next[:, :, :, i] = split_data.spm_next[i]
            actions[:, i] = split_data.actions[i]
        end
        
        # Save to HDF5
        output_path = joinpath(output_dir, "action_vae_$(split_name)_$(timestamp).h5")
        h5open(output_path, "w") do file
            write(file, "spm_current", spm_current)
            write(file, "actions", actions)
            write(file, "spm_next", spm_next)
            write(file, "n_samples", n_samples)
            
            # Save metadata
            densities = [m["density"] for m in split_data.metadata]
            write(file, "densities", densities)
        end
        
        println("💾 Saved $(split_name) data to: $output_path")
        println("   Samples: $n_samples")
    end
    
    println("\\n✅ All splits saved to: $output_dir")
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    # Collect diverse data
    spm_current, actions, spm_next, metadata = collect_diverse_training_data(
        num_episodes_per_density=30,
        steps_per_episode=300,
        exploration_rate=0.2,
        exploration_noise=0.3
    )
    
    # Split into train/val/test
    println("\\n📊 Splitting dataset...")
    splits = split_dataset(spm_current, actions, spm_next, metadata,
        train_ratio=0.7, val_ratio=0.15, test_ratio=0.15)
    
    println("   Train: $(length(splits.train.spm_current)) samples")
    println("   Val:   $(length(splits.val.spm_current)) samples")
    println("   Test:  $(length(splits.test.spm_current)) samples")
    
    # Save data
    save_training_data_with_splits(splits)
end
