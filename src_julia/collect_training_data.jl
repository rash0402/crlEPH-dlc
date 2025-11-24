"""
GRU Training Data Collection Script

Runs a simulation with data collection enabled to generate training data
for the neural SPM predictor.

Usage:
    julia --project=. collect_training_data.jl [num_steps] [num_agents]

Default: 20000 steps, 15 agents
"""

include("main.jl")

using .Types
using .SPM
using .SelfHaze
using .EPH
using .Simulation
using .SPMPredictor
using .DataCollector

# Parse command-line arguments
num_steps = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 20000
num_agents = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 15

println("╔════════════════════════════════════════════════════════════╗")
println("║  GRU Training Data Collection                              ║")
println("╚════════════════════════════════════════════════════════════╝")
println()
println("Configuration:")
println("  Steps:  $num_steps")
println("  Agents: $num_agents")
println()

# Initialize data collector
DataCollector.init_collector()

# Setup with data collection enabled
params = Types.EPHParams(
    predictor_type = :linear,  # Use linear predictor during data collection
    collect_data = true         # Enable data collection
)

env = Types.Environment(400.0, 400.0, grid_size=20)

# Add agents
println("Initializing $num_agents agents...")
for i in 1:num_agents
    x = rand() * env.width
    y = rand() * env.height
    agent = Types.Agent(i, x, y, color=(100, 150, 255))
    push!(env.agents, agent)
end

# Initialize predictor
predictor = SPMPredictor.LinearPredictor(env.dt)

println("Starting data collection...")
print("Progress: ")
flush(stdout)

# Counters
transitions_collected = 0
saves_performed = 0

# Run simulation
for step in 1:num_steps
    # Run simulation step (this will automatically collect data)
    Simulation.step!(env, params, predictor)

    # Progress indicator
    if step % 100 == 0
        print(".")
        flush(stdout)

        # Report progress
        if step % 500 == 0
            current_samples = sum(length(b) for b in values(DataCollector.agent_buffers))
            print(" [$current_samples samples]")
            flush(stdout)
        end
    end
end

println()
println()

# Final data collection statistics
total_samples = sum(length(b) for b in values(DataCollector.agent_buffers))
total_episodes = length(DataCollector.saved_episodes)

println("Data Collection Complete!")
println()
println("Statistics:")
println("  Total transitions: $total_samples")
println("  Saved episodes: $total_episodes")
println("  Active agent buffers: $(length(DataCollector.agent_buffers))")

if total_samples > 0
    println()
    println("Agent-wise breakdown:")
    for (agent_id, buffer) in sort(collect(DataCollector.agent_buffers), by=x->x[1])
        println("  Agent $agent_id: $(length(buffer)) transitions")
    end
end

println()
println("Saving final data...")

# Save remaining data
if total_samples > 0
    filename = DataCollector.save_data("spm_sequences")

    if filename === nothing
        println("⚠️  No data was saved (empty episodes)")
        println()
        println("═══════════════════════════════════════════════════════════")
        println()
        println("⚠️  Data collection completed but no file was saved")
    else
        println("✓ Training data saved!")
        println()
        println("Output file: $filename")

        # Load and verify
        using JLD2
        data = load(filename)

        println()
        println("Verification:")
        if haskey(data, "episodes")
            println("  Total episodes: $(length(data["episodes"]))")
            total_transitions = sum(length(ep["visible_agents"]) for ep in data["episodes"])
            println("  Total transitions: $total_transitions")

            # Sample statistics
            if !isempty(data["episodes"])
                sample_ep = data["episodes"][1]
                println("  Sample SPM shape: $(size(sample_ep["spm_t"]))")
                println("  Sample action shape: $(size(sample_ep["action_t"]))")

                # Check for diverse visible agent counts
                all_counts = [ep["visible_agents"][i] for ep in data["episodes"] for i in 1:length(ep["visible_agents"])]
                println("  Visible agents range: $(minimum(all_counts)) - $(maximum(all_counts))")
                println("  Mean visible agents: $(round(mean(all_counts), digits=2))")
            end
        end

        println()
        println("═══════════════════════════════════════════════════════════")
        println()
        println("✅ Data collection complete!")
        println("   File: $filename")
        println()
        println("  Ready for GRU training")
        println("═══════════════════════════════════════════════════════════")
    end
else
    println("❌ No transitions collected during simulation")
    println("   Check that agents are observing each other and taking actions.")
    exit(1)
end
