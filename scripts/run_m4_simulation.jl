#!/usr/bin/env julia
"""
Run simulation with M4 predictive control enabled.
Short test run to verify functionality.
"""

println("=" ^ 70)
println("🚀 M4 PREDICTIVE CONTROL SIMULATION")
println("=" ^ 70)

# Load project
using Pkg
Pkg.activate(".")

# Load modules
include("../src/config.jl")
include("../src/dynamics.jl")
include("../src/spm.jl")
include("../src/controller.jl")
include("../src/communication.jl")
include("../src/logger.jl")

using .Config
using .Dynamics
using .SPM
using .Controller
using .Communication
using .Logger

# Override control params for M4
println("\n⚙️  Configuration:")
println("  Mode: PREDICTIVE (M4)")
println("  VAE: Enabled")
println("  Steps: 300 (short test)")
println("  Agents per group: 10")

# Create custom params
world_params = WorldParams(max_steps=300)
control_params = ControlParams(
    use_predictive_control=true,  # Enable M4
    use_vae=true
)

println("\n🔄 Starting simulation...")
println("-" ^ 70)

# Initialize
agents = init_agents(AgentParams(), world_params)
spm_config = init_spm()

# Communication
comm = init_communication()

# Logger
log_file = "data/m4_predictive_test.h5"
data_logger = init_logger(log_file, world_params.max_steps, length(agents))

println("✅ Initialization complete")
println("  Agents: $(length(agents))")
println("  Output: $log_file")

# Main loop
try
    for step in 1:world_params.max_steps
        if step % 50 == 0
            println("  Step $step/$(world_params.max_steps)")
        end
        
        # Update each agent
        for agent in agents
            # Compute relative positions and velocities
            other_agents_list = [a for a in agents if a.id != agent.id]
            
            rel_pos = [relative_position(agent.pos, other.pos, world_params) 
                      for other in other_agents_list]
            rel_vel = [other.vel - agent.vel for other in other_agents_list]
            
            # Generate SPM
            spm = generate_spm_3ch(spm_config, rel_pos, rel_vel, 
                                  AgentParams().r_agent, agent.precision)
            
            # Compute action (M4 predictive)
            action = compute_action_predictive(
                agent, spm, other_agents_list,
                control_params, AgentParams(), world_params, spm_config
            )
            
            # Update dynamics
            step!(agent, action, AgentParams(), world_params)
        end
        
        # Log data
        log_step!(data_logger, agents, step)
        
        # Publish to viewers
        if step % 3 == 0
            publish_global(comm, agents)
            if !isempty(agents)
                publish_detail(comm, agents[1], zeros(16,16,3), 0.0, 0.0, 1.0, [0.0, 0.0])
            end
        end
    end
    
    println("\n✅ Simulation complete!")
    
catch e
    println("\n❌ Error during simulation:")
    println(e)
    rethrow(e)
finally
    # Cleanup
    close_logger(data_logger)
    close_communication(comm)
end

println("\n" * "=" ^ 70)
println("📊 SIMULATION SUMMARY")
println("=" ^ 70)
println("  Mode: M4 Predictive Control")
println("  Steps completed: $(world_params.max_steps)")
println("  Output file: $log_file")
println("\n💡 Next: Run compute_metrics.jl to analyze results")
println("=" ^ 70)
