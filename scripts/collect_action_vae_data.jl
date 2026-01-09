#!/usr/bin/env julia

"""
Training Data Collection Script for Action-Conditioned VAE (EPH v5.4)
Collects (y[k], u[k], y[k+1]) tuples from simulation.
"""

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Printf
using Dates
using LinearAlgebra
using BSON
using HDF5

# Load modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/dynamics.jl")
include("../src/controller.jl")

using .Config
using .SPM
using .Dynamics
using .Controller

"""
Collect training data for Action-Conditioned VAE.
Returns arrays of (spm_current, action, spm_next) tuples.
"""
function collect_training_data(;
    num_episodes::Int=50,
    steps_per_episode::Int=200,
    exploration_rate::Float64=0.3,
    exploration_noise::Float64=0.5,
    seed_start::Int=1
)
    # Storage for training data
    spm_current_list = Vector{Array{Float32, 3}}()
    action_list = Vector{Vector{Float32}}()
    spm_next_list = Vector{Array{Float32, 3}}()
    
    # Initialize parameters
    world_params = WorldParams(max_steps=steps_per_episode)
    agent_params = AgentParams()
    spm_params = SPMParams()
    control_params = ControlParams(
        exploration_rate=exploration_rate,
        exploration_noise=exploration_noise
    )
    spm_config = init_spm(spm_params)
    
    println("🎲 Collecting Action-Conditioned VAE training data...")
    println("   Episodes: $num_episodes")
    println("   Steps per episode: $steps_per_episode")
    println("   Exploration rate: $exploration_rate")
    println("   Exploration noise: $exploration_noise")
    println()
    
    for episode in 1:num_episodes
        # Initialize agents with different seeds
        agents = init_agents(agent_params, world_params, seed=seed_start + episode)
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
            @printf("  Episode %3d / %d complete (samples: %d)\n", episode, num_episodes, length(spm_current_list))
        end
    end
    
    println()
    println("✅ Data collection complete!")
    println("   Total samples: $(length(spm_current_list))")
    
    return spm_current_list, action_list, spm_next_list
end

"""
Save collected data to HDF5 file.
"""
function save_training_data(
    spm_current_list::Vector{Array{Float32, 3}},
    action_list::Vector{Vector{Float32}},
    spm_next_list::Vector{Array{Float32, 3}};
    output_path::String="data/action_vae_training.h5"
)
    n_samples = length(spm_current_list)
    
    # Stack arrays
    spm_current = zeros(Float32, 16, 16, 3, n_samples)
    spm_next = zeros(Float32, 16, 16, 3, n_samples)
    actions = zeros(Float32, 2, n_samples)
    
    for i in 1:n_samples
        spm_current[:, :, :, i] = spm_current_list[i]
        spm_next[:, :, :, i] = spm_next_list[i]
        actions[:, i] = action_list[i]
    end
    
    # Ensure directory exists
    mkpath(dirname(output_path))
    
    # Save to HDF5
    h5open(output_path, "w") do file
        write(file, "spm_current", spm_current)
        write(file, "actions", actions)
        write(file, "spm_next", spm_next)
        write(file, "n_samples", n_samples)
    end
    
    println("💾 Saved training data to: $output_path")
    println("   Shape: ($n_samples samples)")
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    # Collect data
    spm_current, actions, spm_next = collect_training_data(
        num_episodes=100,
        steps_per_episode=300,
        exploration_rate=0.2,
        exploration_noise=0.3
    )
    
    # Save data
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    save_training_data(spm_current, actions, spm_next,
        output_path="data/action_vae_training_$(timestamp).h5"
    )
end
