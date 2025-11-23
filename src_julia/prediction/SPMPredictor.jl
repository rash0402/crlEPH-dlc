module SPMPredictor

using LinearAlgebra
using Flux
using Zygote
using JLD2
using FileIO
using ..Types
using ..SPM

export predict_spm, LinearPredictor, NeuralPredictor, load_predictor, Predictor, update_state!

"""
Abstract interface for SPM prediction models.
"""
abstract type Predictor end

"""
    LinearPredictor

Simple linear prediction based on kinematic model.
"""
struct LinearPredictor <: Predictor
    dt::Float64
end

"""
    NeuralPredictor

Neural network based predictor with decomposed GRU layers for manual state management.
"""
struct NeuralPredictor <: Predictor
    dense1::Dense
    cell::GRUCell
    dense2::Dense
    dt::Float64
end

"""
    load_predictor(model_path::String)

Load a trained neural predictor model from file.
Handles both old (Dense-only) and new (GRU) model formats.
"""
function load_predictor(model_path::String)
    if !isfile(model_path)
        error("Model file not found: $model_path")
    end
    
    println("Loading model from: $model_path")
    data = load(model_path)
    model = data["model"]
    
    # Detect model type
    if length(model) == 3
        layer2 = model[2]
        layer2_type_name = string(typeof(layer2))
        
        # Check if it's a Recur type (without requiring Flux.Recur to exist)
        if occursin("Recur", layer2_type_name)
            # New GRU model: Dense -> Recur(GRUCell) -> Dense
            println("  Detected GRU model format (Recur)")
            dense1 = model[1]
            recur = layer2
            dense2 = model[3]
            
            # Extract GRUCell from Recur wrapper
            cell = recur.cell
            
            return NeuralPredictor(dense1, cell, dense2, 0.1)
        elseif occursin("GRUCell", layer2_type_name)
            # Direct GRUCell format: Dense -> GRUCell -> Dense
            println("  Detected GRU model format (GRUCell)")
            dense1 = model[1]
            cell = layer2
            dense2 = model[3]
            
            return NeuralPredictor(dense1, cell, dense2, 0.1)
        end
    end
    
    # Old Dense-only model or incompatible format
    # Fall back to creating a simple GRU model with random initialization
    println("  Warning: Incompatible model format. Creating new GRU model with random initialization.")
    println("  Please train a new GRU model using scripts/update_gru.sh")
    
    # Create a new GRU model with proper architecture
    input_size = 110  # 108 (SPM) + 2 (action)
    hidden_size = 128
    spm_flat_size = 108
    
    dense1 = Dense(input_size => hidden_size, relu)
    cell = GRUCell(hidden_size => hidden_size)
    dense2 = Dense(hidden_size => spm_flat_size)
    
    return NeuralPredictor(dense1, cell, dense2, 0.1)
end

"""
    predict_spm(predictor::LinearPredictor, agent, action, env, spm_params)
"""
function predict_spm(predictor::LinearPredictor, 
                     agent::Types.Agent, 
                     action::Vector{Float64},
                     env::Types.Environment,
                     spm_params::SPM.SPMParams)
    
    # Use Zygote.ignore for LinearPredictor as ray casting is not differentiable
    return Zygote.ignore() do
        # Predict future position (with toroidal wrap)
        pos_pred = agent.position + action * predictor.dt
        pos_pred[1] = mod(pos_pred[1], env.width)
        pos_pred[2] = mod(pos_pred[2], env.height)
        
        # Predict future orientation
        speed = norm(action)
        orientation_pred = if speed > 0.1
            atan(action[2], action[1])
        else
            agent.orientation
        end
        
        # Create virtual agent
        virtual_agent = Types.Agent(
            agent.id,
            pos_pred[1],
            pos_pred[2],
            theta=orientation_pred,
            color=agent.color
        )
        virtual_agent.radius = agent.radius
        virtual_agent.max_speed = agent.max_speed
        
        # Compute SPM
        SPM.compute_spm(virtual_agent, env, spm_params)
    end
end

"""
    update_state!(predictor::NeuralPredictor, agent, spm, action)

Update the internal hidden state of the GRU with the actual observed action and SPM.
"""
function update_state!(predictor::NeuralPredictor, 
                       agent::Types.Agent, 
                       spm::Array{Float64, 3},
                       action::Vector{Float64})
    
    # Prepare input
    spm_flat = reshape(spm, :)
    input = vcat(Float32.(spm_flat), Float32.(action))
    
    # 1. Dense 1
    x1 = predictor.dense1(input)
    
    # 2. GRU Cell
    # Initialize state if needed
    if agent.hidden_state === nothing
        hidden_size = size(predictor.cell.Wi, 1) ÷ 3
        agent.hidden_state = zeros(Float32, hidden_size)
    end
    
    h = agent.hidden_state
    h_new, _ = predictor.cell(h, x1)
    
    # Update agent state
    agent.hidden_state = h_new
end

function update_state!(predictor::LinearPredictor, agent, spm, action)
    # No state to update
end

"""
    predict_spm(predictor::NeuralPredictor, agent, action, env, spm_params)

Predict future SPM using trained neural network (GRU).
Uses current hidden state WITHOUT mutating it (1-step lookahead).
"""
function predict_spm(predictor::NeuralPredictor, 
                     agent::Types.Agent, 
                     action::Vector{Float64},
                     env::Types.Environment,
                     spm_params::SPM.SPMParams)
    
    # Prepare input: [SPM_flat; Action]
    if agent.current_spm === nothing
        return predict_spm(LinearPredictor(predictor.dt), agent, action, env, spm_params)
    end
    
    spm_flat = reshape(agent.current_spm, :)
    input = vcat(Float32.(spm_flat), Float32.(action))
    
    # --- Stateful Prediction Logic ---
    
    # 1. Dense Layer 1
    x1 = predictor.dense1(input)
    
    # 2. GRU Layer (Peek)
    if agent.hidden_state === nothing
        # Should have been initialized by update_state!, but if not (first step), use zeros
        hidden_size = size(predictor.cell.Wi, 1) ÷ 3
        h = zeros(Float32, hidden_size)
    else
        h = agent.hidden_state
    end
    
    # Compute next state without mutation
    h_new, x2 = predictor.cell(h, x1)
    
    # 3. Dense Layer 2
    output = predictor.dense2(x2)
    
    # 4. Reshape
    # Reshape back to (3, 6, 6) - Channel first
    spm_raw = reshape(Float64.(output), 3, 6, 6)
    
    # Ensure non-negative occupancy (channel 1) without mutation
    occ = max.(0.0, spm_raw[1:1, :, :])
    vel = spm_raw[2:3, :, :]
    
    spm_pred = cat(occ, vel, dims=1)
    
    return spm_pred
end

end
