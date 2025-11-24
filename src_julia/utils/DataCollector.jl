module DataCollector

using JLD2
using FileIO
using Dates

export Transition, collect_transition, save_data, init_collector

"""
    Transition

Data structure representing a single state transition for training.
Stores (State_t, Action_t, State_{t+1}).
"""
struct Transition
    spm::Array{Float64, 3}
    action::Vector{Float64}
    next_spm::Array{Float64, 3}
    visible_agents_count::Int  # Number of agents in FOV (for importance weighting)
end

# Global storage for sequences (per agent)
const agent_buffers = Dict{Int, Vector{Transition}}()
const saved_episodes = Vector{Vector{Transition}}()

# Target agent IDs for data collection (nothing = collect all agents)
const target_agent_ids = Ref{Union{Vector{Int}, Nothing}}(nothing)

"""
    init_collector(target_ids::Union{Int, Vector{Int}, Nothing} = nothing)

Initialize/clear the data collector.

Args:
    target_ids: If specified, only collect data from these agent IDs.
                Can be a single Int, a Vector{Int}, or nothing (collect all agents).
"""
function init_collector(target_ids::Union{Int, Vector{Int}, Nothing} = nothing)
    empty!(agent_buffers)
    empty!(saved_episodes)

    # Convert single Int to Vector{Int}
    if target_ids isa Int
        target_agent_ids[] = [target_ids]
    else
        target_agent_ids[] = target_ids
    end
end

"""
    collect_transition(agent_id, spm, action, next_spm, visible_agents_count)

Record a single transition for an agent with importance weight based on FOV occupancy.
Only collects data if agent_id matches target_agent_ids (or if target_agent_ids is nothing).
"""
function collect_transition(agent_id::Int,
                           spm::Union{Array{Float64, 3}, Nothing},
                           action::Union{Vector{Float64}, Nothing},
                           next_spm::Union{Array{Float64, 3}, Nothing},
                           visible_agents_count::Int=0)

    # Filter by target agent IDs
    if target_agent_ids[] !== nothing && !(agent_id in target_agent_ids[])
        return
    end

    if spm === nothing || action === nothing || next_spm === nothing
        return
    end

    # Create transition with importance weight
    transition = Transition(spm, action, next_spm, visible_agents_count)

    # Add to agent's buffer
    if !haskey(agent_buffers, agent_id)
        agent_buffers[agent_id] = Transition[]
    end
    push!(agent_buffers[agent_id], transition)
end

"""
    save_data(filename_prefix="spm_sequences")

Save collected sequences to a JLD2 file.
"""
function save_data(filename_prefix::String="spm_sequences")
    # Move current buffers to saved episodes
    for (id, buffer) in agent_buffers
        if !isempty(buffer)
            push!(saved_episodes, copy(buffer))
            empty!(buffer)
        end
    end

    if isempty(saved_episodes)
        println("No data to save.")
        return nothing
    end
    
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    # Use absolute path relative to project root (parent of src_julia/)
    project_root = dirname(dirname(@__DIR__))
    filename = joinpath(project_root, "data", "training", "$(filename_prefix)_$(timestamp).jld2")

    mkpath(dirname(filename))
    
    # Save as Vector of Vectors (Sequences)
    # We need to be careful with JLD2 and custom structs.
    # Let's convert to simple arrays of arrays or a 4D array if lengths are equal.
    # Since lengths might differ (if agents added/removed), let's save as list of dicts/arrays.
    
    # Format: List of episodes. Each episode is a Dict with "spm_t", "action_t", "spm_next", "visible_agents"
    # spm_t: (3, 6, 6, T)
    
    formatted_data = []
    
    for episode in saved_episodes
        T = length(episode)
        if T == 0 continue end
        
        spm_size = size(episode[1].spm)
        action_size = length(episode[1].action)
        
        spm_t_arr = zeros(Float64, spm_size..., T)
        action_t_arr = zeros(Float64, action_size, T)
        spm_next_arr = zeros(Float64, spm_size..., T)
        visible_agents_arr = zeros(Int, T)
        
        for (i, t) in enumerate(episode)
            spm_t_arr[:,:,:,i] = t.spm
            action_t_arr[:,i] = t.action
            spm_next_arr[:,:,:,i] = t.next_spm
            visible_agents_arr[i] = t.visible_agents_count
        end
        
        push!(formatted_data, Dict(
            "spm_t" => spm_t_arr,
            "action_t" => action_t_arr,
            "spm_next" => spm_next_arr,
            "visible_agents" => visible_agents_arr
        ))
    end
    
    save(filename, Dict("episodes" => formatted_data))

    println("Saved $(length(formatted_data)) episodes to $(filename)")
    empty!(saved_episodes)

    return filename
end

end
