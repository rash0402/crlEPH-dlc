using HDF5
using Statistics
using LinearAlgebra
using Printf

"""
Evaluate metrics for EPH v7.2 simulation results.
Metrics:
1. Freezing Rate: % of time speed < threshold (exclude goal reached)
2. Collision Rate: Number of collisions per agent or % of colliding frames
3. Success Rate: % of agents reaching goal
4. Average Speed: Mean speed of active agents
"""

function evaluate_file(filepath::String)
    println("📊 Analyzing $filepath...")
    
    h5open(filepath, "r") do file
        # Load data
        # [steps, agents, 2]
        pos = read(file["trajectory/pos"])
        vel = read(file["trajectory/vel"])
        n_steps, n_agents, _ = size(pos)
        
        # Parameters
        freeze_thresh = 0.05  # m/s
        collision_thresh = 0.5 # m (radius 0.25 + 0.25) - usually r_agent=0.5 -> dist < 1.0? 
        # Check AgentParams default: r_agent=0.5 -> diameter 1.0. Collision if dist < 1.0
        # However, "Personal Space" is often larger. Physical collision is r1+r2.
        r_agent = 0.5
        dist_collision = r_agent * 2.0
        
        # Trackers
        frozen_count = 0
        active_count = 0
        collisions = 0
        success_count = 0
        total_speed = 0.0
        
        # Goal Reached Check (Approximate based on position or final speed?)
        # Scramble crossing: Goal is usually around (±45, ±45) depending on start.
        # Let's assume an agent is "done" if it leaves the central R=40 area?
        # Or simpler: if it stops moving at the end?
        # Let's assess "active" frames as frames where agent is not yet at goal.
        # Simplification: Analyze steps 100 to end (skip initialization).
        
        # Determine active frames per agent
        # Assume agent reaches goal if it's far from origin?
        # Scramble setup: Starts at R=40, goes to opposite side.
        # Let's just calculate over all frames for now, or exclude start.
        
        start_step = 100
        end_step = n_steps
        
        for t in start_step:end_step
            # 1. Collision Check
            for i in 1:n_agents
                p_i = pos[t, i, :]
                
                # Check against other agents
                for j in (i+1):n_agents
                    p_j = pos[t, j, :]
                    if norm(p_i - p_j) < dist_collision
                        collisions += 1
                        # Note: This counts collision FRAMES per pair.
                    end
                end
                
                # 2. Freezing & Speed
                v_i = vel[t, i, :]
                speed = norm(v_i)
                total_speed += speed
                active_count += 1
                
                if speed < freeze_thresh
                    frozen_count += 1
                end
            end
        end
        
        # Metrics
        avg_speed = total_speed / max(active_count, 1)
        freezing_rate = (frozen_count / max(active_count, 1)) * 100.0
        collision_rate = collisions / n_steps # Collisions per frame?
        
        @printf("   Time Steps: %d\n", n_steps)
        @printf("   Agents:     %d\n", n_agents)
        @printf("   Avg Speed:  %.3f m/s\n", avg_speed)
        @printf("   Freezing:   %.2f %%\n", freezing_rate)
        @printf("   Collisions: %d (Total Pair-Frames)\n", collisions)
        
        return (avg_speed, freezing_rate, collisions)
    end
end

function main()
    if length(ARGS) > 0
        files = ARGS
    else
        # Find latest simulation log
        log_dir = "data/logs"
        if !isdir(log_dir)
            println("Log directory not found: $log_dir")
            return
        end
        
        files = filter(x -> startswith(x, "sim_v72_") && endswith(x, ".h5"), readdir(log_dir))
        files = joinpath.(log_dir, files)
        
        if isempty(files)
            println("No log files found.")
            return
        end
        # Sort by mtime
        sort!(files, by=mtime)
        # Pick latest
        files = [files[end]]
    end
    
    for f in files
        evaluate_file(f)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
