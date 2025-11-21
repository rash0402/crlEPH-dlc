module Simulation

using ..Types
using ..MathUtils
using ..SPM
using ..EPH
using LinearAlgebra
using Random

export initialize_simulation, step!

function initialize_simulation(;width=800.0, height=800.0, n_agents=20)
    env = Environment(width, height)
    
    # Scramble Crossing Setup
    center_x, center_y = width / 2, height / 2
    spawn_dist = 150.0
    
    directions = [
        (name="North", spawn=[center_x, center_y - spawn_dist], goal=[center_x, center_y + spawn_dist], color=(255, 100, 100)),
        (name="South", spawn=[center_x, center_y + spawn_dist], goal=[center_x, center_y - spawn_dist], color=(100, 255, 100)),
        (name="East", spawn=[center_x + spawn_dist, center_y], goal=[center_x - spawn_dist, center_y], color=(100, 100, 255)),
        (name="West", spawn=[center_x - spawn_dist, center_y], goal=[center_x + spawn_dist, center_y], color=(255, 255, 100))
    ]
    
    agents_per_dir = div(n_agents, 4)
    id_counter = 1
    
    for dir in directions
        for i in 1:agents_per_dir
            # Random spread
            if dir.name in ["North", "South"]
                x = dir.spawn[1] + rand() * 60 - 30
                y = dir.spawn[2] + rand() * 40 - 20
            else
                x = dir.spawn[1] + rand() * 40 - 20
                y = dir.spawn[2] + rand() * 60 - 30
            end
            
            theta = rand() * 2π - π
            agent = Agent(id_counter, x, y, theta=theta, color=dir.color)
            
            # Goal
            gx = dir.goal[1] + rand() * 60 - 30
            gy = dir.goal[2] + rand() * 60 - 30
            agent.goal = [gx, gy]
            
            agent.personal_space = 15.0 + rand() * 20.0
            
            push!(env.agents, agent)
            id_counter += 1
        end
    end
    
    return env
end

function step!(env::Environment)
    # 1. Sense & Decide
    spm_params = SPM.SPMParams(d_max=300.0)
    controller = EPH.GradientEPHController()
    
    for agent in env.agents
        # Sense
        spm = SPM.compute_spm(agent, env, spm_params)
        prec = SPM.get_precision_matrix(agent, spm_params)
        
        agent.current_spm = spm
        agent.current_precision = prec
        
        # Haze (simplified)
        grid_x = clamp(floor(Int, agent.position[1] / env.grid_size) + 1, 1, size(env.haze_grid, 1))
        grid_y = clamp(floor(Int, agent.position[2] / env.grid_size) + 1, 1, size(env.haze_grid, 2))
        env_haze = env.haze_grid[grid_x, grid_y]
        
        # Preferred Velocity
        pref_vel = nothing
        if agent.goal !== nothing
            dx, dy, dist = toroidal_distance(agent.position, agent.goal, env.width, env.height)
            if dist > 0
                pref_vel = [dx / dist * agent.max_speed, dy / dist * agent.max_speed]
            end
        end
        
        # Decide
        action = EPH.decide_action(controller, agent, spm, prec, env_haze, pref_vel)
        agent.velocity = action
        
        # Update Haze (Trail) - Increased deposition
        env.haze_grid[grid_x, grid_y] = min(1.0, env.haze_grid[grid_x, grid_y] + 0.2)
    end
    
    # 2. Update Physics
    dt = env.dt
    for agent in env.agents
        # Update Position
        agent.position += agent.velocity * dt
        
        # Wrap around (Toroidal)
        agent.position[1] = mod(agent.position[1], env.width)
        agent.position[2] = mod(agent.position[2], env.height)
        
        # Update Orientation
        speed = norm(agent.velocity)
        if speed > 0.1
            agent.orientation = atan(agent.velocity[2], agent.velocity[1])
        end
    end
    
    # 3. Resolve Collisions (Simple elastic)
    _resolve_collisions!(env)
    
    # 4. Decay Haze
    env.haze_grid *= 0.99
    
    # 5. Respawn logic (Simplified)
    for agent in env.agents
        if agent.goal !== nothing
            dx, dy, dist = toroidal_distance(agent.position, agent.goal, env.width, env.height)
            if dist < 20.0
                # Reached goal, respawn at random start
                # For simplicity, just swap goal and spawn roughly
                # Or just reverse goal
                agent.goal, agent.position = agent.position, agent.goal
                # Actually, let's just reset to a random edge for continuous flow
                # But swapping is easier to implement without directions struct here.
                # Let's just reverse velocity and set new goal far away?
                # No, let's keep it simple: Just reverse goal direction
                # agent.goal = [env.width - agent.goal[1], env.height - agent.goal[2]]
            end
        end
    end
end

function _resolve_collisions!(env::Environment)
    for i in 1:length(env.agents)
        for j in (i+1):length(env.agents)
            a1 = env.agents[i]
            a2 = env.agents[j]
            
            dx, dy, dist = toroidal_distance(a1.position, a2.position, env.width, env.height)
            min_dist = a1.radius + a2.radius
            
            if dist < min_dist
                # Collision
                overlap = min_dist - dist
                
                # Push apart
                nx = dx / dist
                ny = dy / dist
                
                # Move a1
                a1.position[1] -= nx * overlap * 0.5
                a1.position[2] -= ny * overlap * 0.5
                
                # Move a2
                a2.position[1] += nx * overlap * 0.5
                a2.position[2] += ny * overlap * 0.5
            end
        end
    end
end

end
