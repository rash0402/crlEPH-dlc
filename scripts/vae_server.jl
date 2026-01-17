#!/usr/bin/env julia
"""
VAE Prediction Server for Python GUI
Receives SPM and action via stdin, returns predicted SPM via stdout
"""

using Pkg
Pkg.activate(".")

using Flux
using BSON: @load
using JSON
using Statistics

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/action_vae.jl")
include("../src/trajectory_loader.jl")

using .Config
using .SPM
using .ActionVAEModel

# Load model
const MODEL_PATH = "models/action_vae_v72_best.bson"
println(stderr, "Loading model from $MODEL_PATH...")
@load MODEL_PATH model
model = cpu(model)
println(stderr, "Model loaded successfully.")

# SPM config
const SPM_PARAMS = SPMParams(n_rho=12, n_theta=12, sensing_ratio=3.0)
const SPM_CONFIG = SPMConfig(
    SPM.init_spm(SPM_PARAMS).rho_grid,
    SPM.init_spm(SPM_PARAMS).theta_grid,
    log(SPM_PARAMS.sensing_ratio),
    SPM_PARAMS
)
const AGENT_PARAMS = AgentParams()

# Signal ready
println("READY")
flush(stdout)

# Main loop
while true
    line = readline()
    if isempty(line) || line == "EXIT"
        break
    end
    
    try
        request = JSON.parse(line)
        cmd = get(request, "cmd", "")
        
        if cmd == "predict"
            # Get SPM and action
            spm_flat = Float32.(request["spm"])
            action_raw = request["action"]
            println(stderr, "DEBUG: action length = $(length(action_raw))")
            println(stderr, "DEBUG: action content = $(action_raw)")
            action = Float32.(action_raw) ./ 150.0f0  # Normalize
            
            # Reshape SPM: Python sends flattened data using order='F' (column-major)
            # So we can directly reshape in Julia (also column-major)
            spm = reshape(spm_flat, 12, 12, 3, 1)
            action_batch = reshape(action, 2, 1)
            
            # Predict
            pred, μ, logσ = model(spm, action_batch)
            
            # Compute haze
            variance = exp.(2 .* logσ)
            haze = mean(variance)
            
            # Output - Python will use order='F' to interpret column-major data
            result = Dict(
                "status" => "ok",
                "prediction" => vec(pred),
                "haze" => haze
            )
            println(JSON.json(result))
            
        elseif cmd == "reconstruct_spm"
            # Reconstruct SPM from trajectory data
            # Python sends pos as [[x1,y1], [x2,y2], ...] which becomes Vector{Vector} in JSON
            # Convert to Matrix [N, 2]
            pos_raw = request["pos"]
            vel_raw = request["vel"]
            n_agents = length(pos_raw)
            
            pos = zeros(n_agents, 2)
            vel = zeros(n_agents, 2)
            for i in 1:n_agents
                pos[i, 1] = pos_raw[i][1]
                pos[i, 2] = pos_raw[i][2]
                vel[i, 1] = vel_raw[i][1]
                vel[i, 2] = vel_raw[i][2]
            end
            
            heading = Float64.(request["heading"])  # [N]
            
            # Obstacles: [[xmin, xmax, ymin, ymax], ...]
            obs_raw = request["obstacles"]
            if length(obs_raw) > 0
                obstacles = zeros(length(obs_raw), 4)
                for i in 1:length(obs_raw)
                    obs_item = obs_raw[i]
                    # Handle both Vector and tuple formats
                    if obs_item isa AbstractVector || obs_item isa Tuple
                        for j in 1:min(4, length(obs_item))
                            obstacles[i, j] = Float64(obs_item[j])
                        end
                    else
                        println(stderr, "WARNING: Unexpected obstacle format at index $i: $(typeof(obs_item))")
                    end
                end
            else
                obstacles = zeros(0, 4)
            end
            
            agent_idx = request["agent_idx"]
            
            spm = reconstruct_spm_at_timestep(
                pos, vel, heading, obstacles,
                agent_idx, SPM_CONFIG, AGENT_PARAMS.r_agent
            )
            
            # Output - Python will use order='F' to interpret column-major data
            result = Dict(
                "status" => "ok",
                "spm" => vec(spm)
            )
            println(JSON.json(result))
            
        else
            println(JSON.json(Dict("status" => "error", "message" => "Unknown command: $cmd")))
        end
        
    catch e
        bt = catch_backtrace()
        msg = sprint(showerror, e, bt)
        println(stderr, "ERROR: $msg")
        println(JSON.json(Dict("status" => "error", "message" => msg)))
    end
    
    flush(stdout)
end
