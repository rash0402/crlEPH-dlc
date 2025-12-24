#!/usr/bin/env julia
"""
Simplified Ablation Study Runner
Compares A1 (baseline) vs A4 (EPH) with multiple seeds.
"""

using Printf
using Dates

println("=" ^ 70)
println("🔬 ABLATION STUDY: A1 (Baseline) vs A4 (EPH)")
println("=" ^ 70)

# Configuration
NUM_SEEDS = 3
MAX_STEPS = 500  # Shorter for quick validation
CONDITIONS = ["a1_baseline", "a4_eph"]

println("\n📋 Configuration:")
println("  Conditions: A1 (baseline), A4 (EPH)")
println("  Seeds: $NUM_SEEDS")
println("  Steps: $MAX_STEPS")
println("  Output: results/ablation/")

# Create output directories
mkpath("results/ablation/a1_baseline")
mkpath("results/ablation/a4_eph")

# Track results
all_results = []

total_experiments = length(CONDITIONS) * NUM_SEEDS
current = 0

for condition in CONDITIONS
    for seed in 1:NUM_SEEDS
        current += 1
        @printf("\n[%d/%d] Running: %s, seed %03d\n", current, total_experiments, condition, seed)
        println("-" ^ 70)
        
        # Prepare simulation script with parameters
        condition_str = condition
        seed_str = seed
        max_steps_str = MAX_STEPS
        
        sim_script = """
        # Temporary simulation script for ablation study
        push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
        
        using Random
        using Dates
        Random.seed!($seed_str)
        
        # Load modules
        include("../src/config.jl")
        include("../src/dynamics.jl")
        include("../src/spm.jl")
        include("../src/controller.jl")
        include("../src/communication.jl")
        include("../src/logger.jl")
        include("../src/vae.jl")
        
        using .Config
        using .Dynamics
        using .SPM
        using .Controller
        using .Communication
        using .Logger
        using .VAEModel
        using BSON
        
        # Configuration for $condition_str
        world_params = WorldParams(max_steps=$max_steps_str)
        agent_params = DEFAULT_AGENT
        spm_params = DEFAULT_SPM
        comm_params = DEFAULT_COMM
        
        # Condition-specific control params
        if "$condition_str" == "a1_baseline"
            control_params = ControlParams(
                experiment_condition=A1_BASELINE,
                use_vae=false
            )
        else  # a4_eph
            control_params = ControlParams(
                experiment_condition=A4_EPH,
                use_vae=true
            )
        end
        
        # Initialize
        agents = init_agents(agent_params, world_params)
        obstacles = init_obstacles(world_params)
        spm_config = init_spm(spm_params)
        publisher = init_publisher(comm_params)
        
        # Logger
        log_file = "results/ablation/$condition_str/seed_$(lpad($seed_str, 3, '0')).h5"
        data_logger = init_logger(log_file, world_params.max_steps, length(agents))
        
        # Load VAE if needed
        vae_model = nothing
        if control_params.use_vae
            try
                vae_data = BSON.load("models/vae_latest.bson")
                vae_model = vae_data[:model]
                println("✅ VAE loaded")
            catch e
                println("⚠️  VAE not available")
            end
        end
        
        # Main loop
        println("▶️  Running simulation...")
        for step in 1:world_params.max_steps
            if step % 100 == 0
                @printf("  Step %d/%d\\\\n", step, world_params.max_steps)
            end
            
            for agent in agents
                # Get other agents
                other_agents = [a for a in agents if a.id != agent.id]
                
                # Compute relative positions and velocities
                rel_pos = [relative_position(agent.pos, other.pos, world_params) 
                          for other in other_agents]
                rel_vel = [other.vel - agent.vel for other in other_agents]
                
                # Generate SPM
                spm = generate_spm_3ch(spm_config, rel_pos, rel_vel, 
                                      agent_params.r_agent, agent.precision)
                
                # Compute action
                action = compute_action(agent, spm, control_params, agent_params)
                
                # Update dynamics
                step!(agent, action, agent_params, world_params)
                
                # Update precision if VAE available
                if vae_model !== nothing
                    spm_input = reshape(spm, 16, 16, 3, 1)
                    haze_val = compute_haze(vae_model, spm_input)
                    agent.precision = 1.0 / (Float64(haze_val[1]) + control_params.epsilon)
                end
            end
            
            # Log all agents
            log_step!(data_logger, agents, step)
            
            # Publish (every 10 steps to reduce overhead)
            if step % 10 == 0
                publish_global(publisher, agents, step, comm_params)
            end
        end
        
        # Cleanup
        close_logger(data_logger)
        close_publisher(publisher)
        
        println("✅ Simulation complete")
        """
        
        # Write temporary script
        temp_script = "temp_sim_$(condition)_$(seed).jl"
        open(temp_script, "w") do io
            write(io, sim_script)
        end
        
        # Run simulation
        try
            run(`julia --project=. $temp_script`)
            println("✅ Completed")
            
            # Compute metrics
            log_file = "results/ablation/$(condition)/seed_$(lpad(seed, 3, '0')).h5"
            metrics_file = "results/ablation/$(condition)/seed_$(lpad(seed, 3, '0'))_metrics.json"
            
            println("📊 Computing metrics...")
            run(`julia --project=. scripts/compute_metrics.jl $log_file $metrics_file`)
            
            push!(all_results, (condition, seed, metrics_file))
            
        catch e
            println("❌ Error: $e")
        finally
            # Cleanup temp script
            rm(temp_script, force=true)
        end
    end
end

println("\n" * "=" ^ 70)
println("✅ ABLATION STUDY COMPLETE")
println("=" ^ 70)

println("\n📊 Results:")
for (cond, seed, file) in all_results
    println("  $cond seed $seed: $file")
end

println("\n💡 Next Steps:")
println("  1. julia --project=. scripts/aggregate_results.jl")
println("  2. julia --project=. scripts/statistical_analysis.jl")
println("=" ^ 70)
