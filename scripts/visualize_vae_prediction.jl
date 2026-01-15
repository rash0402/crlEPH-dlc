#!/usr/bin/env julia
using Pkg
Pkg.activate(".")

using Flux
using BSON: @load
using HDF5
using Plots
using Statistics
using Random

# Set headless plotting
ENV["GKSwstype"] = "100"

# Load project modules
include("../src/config.jl")
include("../src/spm.jl")
include("../src/action_vae.jl")
include("../src/trajectory_loader.jl")

using .Config
using .SPM
using .ActionVAEModel

# Constants
const MODEL_PATH = "models/action_vae_v72_best.bson"
const DATA_DIR = "data/vae_training/raw_v72"
const OUTPUT_DIR = "results/vae_vis"
mkpath(OUTPUT_DIR)

function visualize_predictions()
    println("Loading model from $MODEL_PATH...")
    if !isfile(MODEL_PATH)
        error("Model file not found! Run training first.")
    end
    
    # Load model
    @load MODEL_PATH model
    # Ensure model is on CPU
    model = cpu(model)
    
    println("Loading data from $DATA_DIR...")
    # Load one file for visualization
    files = readdir(DATA_DIR, join=true)
    if isempty(files)
        error("No data files found.")
    end
    
    # Load the first file (usually has enough data)
    filepath = files[1]
    println("  Using file: $filepath")
    
    data = load_trajectory_data(filepath)
    # Reconstruct SPM for validation
    pos = data.pos
    vel = data.vel
    heading = data.heading
    obstacles = data.obstacles
    u = data.u
    
    T, N, _ = size(pos)
    
    # Parameters for reconstruction
    spm_params = SPMParams(n_rho=12, n_theta=12, sensing_ratio=3.0)
    config = SPMConfig(SPM.init_spm(spm_params).rho_grid, SPM.init_spm(spm_params).theta_grid, log(spm_params.sensing_ratio), spm_params)
    agent_params = AgentParams()
    
    # Collect some samples (Pairs of y_t, u_t, y_t+1)
    samples = []
    
    # Pick random agents and time steps
    # We want cases with non-zero movement to see interesting predictions
    rng = MersenneTwister(42)
    
    println("Selecting samples...")
    for _ in 1:5
        t = rand(rng, 1:T-5)
        agent_idx = rand(rng, 1:N)
        
        # Check if moving (action magnitude > 10)
        action = u[t, agent_idx, :]
        if norm(action) < 10.0
            continue # Skip boring stationary samples
        end
        
        # Reconstruct Current (t)
        spm_t = reconstruct_spm_at_timestep(
            pos[t, :, :], vel[t, :, :], heading[t, :], obstacles,
            agent_idx, config, agent_params.r_agent
        )
        
        # Reconstruct Next (t+5) - matching training Stride=5
        if t+5 > T continue end
        spm_next = reconstruct_spm_at_timestep(
            pos[t+5, :, :], vel[t+5, :, :], heading[t+5, :], obstacles,
            agent_idx, config, agent_params.r_agent
        )
        
        push!(samples, (spm_t, action, spm_next, t, agent_idx))
    end
    
    if isempty(samples)
        println("No interesting samples found, taking random ones.")
        t = 10
        agent_idx = 1
         # Reconstruct Current (t)
        spm_t = reconstruct_spm_at_timestep(
            pos[t, :, :], vel[t, :, :], heading[t, :], obstacles,
            agent_idx, config, agent_params.r_agent
        )
        # Reconstruct Next (t+5)
        spm_next = reconstruct_spm_at_timestep(
            pos[t+5, :, :], vel[t+5, :, :], heading[t+5, :], obstacles,
            agent_idx, config, agent_params.r_agent
        )
        action = u[t, agent_idx, :]
        push!(samples, (spm_t, action, spm_next, t, agent_idx))
    end
    
    println("Generating plots for $(length(samples)) samples...")
    
    for (idx, (y_t, action, y_next_true, t, agent_id)) in enumerate(samples)
        # Prepare input batch
        y_t_batch = reshape(Float32.(y_t), 12, 12, 3, 1) # (H, W, C, B)
        action_batch = reshape(Float32.(action) ./ 150.0f0, 2, 1)    # (U, B) Normalized
        
        # Predict
        y_next_pred_batch, μ, logσ = model(y_t_batch, action_batch)
        y_next_pred = y_next_pred_batch[:, :, :, 1] # Extract (H, W, C)
        
        # Plotting
        # Layout: 3 rows (True, Pred, AbsDiff) x 3 columns (Channels)
        plots = []
        titles = ["Occupancy", "Proximity", "Risk"]
        
        max_val = maximum(vcat(y_next_true, y_next_pred))
        
        for ch in 1:3
            # True
            p1 = heatmap(y_next_true[:, :, ch], clims=(0, max_val), title="True $(titles[ch])", aspect_ratio=:equal, c=:viridis)
            push!(plots, p1)
            
            # Pred
            p2 = heatmap(y_next_pred[:, :, ch], clims=(0, max_val), title="Pred $(titles[ch])", aspect_ratio=:equal, c=:viridis)
            push!(plots, p2)
            
            # Diff
            diff = abs.(y_next_true[:, :, ch] - y_next_pred[:, :, ch])
            p3 = heatmap(diff, title="Diff $(titles[ch])", aspect_ratio=:equal, c=:heat)
            push!(plots, p3)
        end
        
        # Combine
        # Order in `plots`: [T1, P1, D1, T2, P2, D2, T3, P3, D3]
        # We want rows: True, Pred, Diff
        # So we want [T1, T2, T3; P1, P2, P3; D1, D2, D3]
        final_layout = [plots[1] plots[4] plots[7];
                        plots[2] plots[5] plots[8];
                        plots[3] plots[6] plots[9]]
        
        plot_title = "VAE Pred sample $idx (A=$agent_id, T=$t)\nAction: $(round.(action, digits=2))"
        final_plot = plot(final_layout..., layout=(3, 3), size=(1200, 1200), plot_title=plot_title)
        
        # Save
        outfile = joinpath(OUTPUT_DIR, "vae_pred_sample_$(idx).png")
        savefig(final_plot, outfile)
        println("  Saved: $outfile")
    end
end

visualize_predictions()
