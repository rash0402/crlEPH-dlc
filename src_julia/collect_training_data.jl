"""
GRU Training Data Collection Script

Runs a simulation with data collection enabled to generate training data
for the neural SPM predictor.

Data Collection Strategy:
- **Configurable multi-agent collection**:
  → GUI allows selecting how many agents to collect from (1 to all agents)
  → Default: Collect from ALL agents for maximum diversity
  → More agents = more diverse data = better learning
  → No additional computation time (parallel collection)
- **Optimal balance**: Each agent provides full trajectory over simulation
  → Long enough for temporal learning (e.g., 20,000 steps/agent)
  → Extremely diverse for robustness (multiple independent trajectories)
- **Training strategy**: 80% of agents for training, 20% for testing
  → Example: 15 agents → 12 for train, 3 for test
  → Proper overfitting detection
- **Long episodes**: No frequent auto-saves (threshold: 50000 samples)
  → Better captures temporal correlations

Optimizations for fast data collection:
- **LinearPredictor**: CRITICAL for bootstrapping (avoids chicken-and-egg problem)
  → Cannot use GRU during initial data collection (GRU doesn't exist yet)
  → Linear predictor provides baseline predictions for training data
  → This is the ONLY scenario where Linear predictor should be used
  → After GRU training, all simulations use GRU (80x better accuracy)
- No ZeroMQ visualization
- No experiment logging
- Increased max_speed and max_accel for faster agent movement
- Larger dt (0.15 vs 0.1) for fewer simulation steps per second
- Reduced max_iter (3 vs 5) for faster gradient descent

Usage:
    julia --project=. collect_training_data.jl [num_steps] [num_agents]

    Environment variable:
      EPH_COLLECT_AGENTS=N  - Collect data from first N agents (default: all agents)

Default: 20000 steps, 15 agents, collect from all agents
Example: EPH_COLLECT_AGENTS=5 julia collect_training_data.jl 10000 15
         → Collects from agents 1-5 only
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
# Read target collection count from environment variable
collect_agents = parse(Int, get(ENV, "EPH_COLLECT_AGENTS", string(num_agents)))
collect_agents = min(collect_agents, num_agents)  # Can't collect more than total agents

target_agents = collect(1:collect_agents)
DataCollector.init_collector(target_agents)

println("Data collection targets: Agents $target_agents ($(length(target_agents)) agents)")
println("  → Collecting from $(length(target_agents)) agents provides:")
println("    • $(length(target_agents))x more data samples (vs single-agent)")
println("    • Maximum diversity: $(length(target_agents)) different initial positions and scenarios")
println("    • Best generalization performance")
println("    • Same simulation time (parallel collection)")
println()

# Setup with data collection enabled (optimized for speed)
params = Types.EPHParams(
    predictor_type = :linear,  # Use linear predictor during data collection
    collect_data = true,        # Enable data collection
    max_speed = 80.0,          # Increased for faster movement (default: 50.0)
    max_accel = 150.0,         # Increased for quicker acceleration (default: 100.0)
    max_iter = 3               # Reduced iterations for faster computation (default: 5)
)

env = Types.Environment(400.0, 400.0, grid_size=20, dt=0.15)  # Larger timestep for speed

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
println()

# Counters
transitions_collected = 0
saves_performed = 0
last_report_time = time()

# Run simulation
for step in 1:num_steps
    # Run simulation step (this will automatically collect data)
    Simulation.step!(env, params, predictor)

    # Progress indicator (every 500 steps or every 5 seconds)
    current_time = time()
    if step % 500 == 0 || (current_time - last_report_time) >= 5.0
        current_samples = sum(length(b) for b in values(DataCollector.agent_buffers); init=0)
        progress_pct = round(100 * step / num_steps, digits=1)
        println("Progress: $step / $num_steps ($progress_pct%) - Collected: $current_samples samples")
        flush(stdout)
        global last_report_time = current_time
    end
end

println()
println()

# Final data collection statistics
total_samples = sum(length(b) for b in values(DataCollector.agent_buffers); init=0)
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
