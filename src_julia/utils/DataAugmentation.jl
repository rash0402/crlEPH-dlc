module DataAugmentation

using LinearAlgebra

export augment_spm_transition, rotate_spm, flip_spm, rotate_action, flip_action

"""
    rotate_spm(spm::Array{Float64, 3}, shift::Int)

Rotate SPM by circularly shifting the angular dimension.
shift: number of angular bins to shift (0 to Nθ-1)
"""
function rotate_spm(spm::Array{Float64, 3}, shift::Int)
    # SPM shape: (3, Nr, Nθ)
    Nθ = size(spm, 3)
    shift = mod(shift, Nθ)  # Ensure shift is in valid range
    
    if shift == 0
        return copy(spm)
    end
    
    # Circular shift along angular dimension (dim 3)
    return circshift(spm, (0, 0, shift))
end

"""
    flip_spm(spm::Array{Float64, 3})

Flip SPM left-right (mirror across forward direction).
This reverses the angular bins and negates tangential velocity.
"""
function flip_spm(spm::Array{Float64, 3})
    # SPM shape: (3, Nr, Nθ)
    spm_flipped = copy(spm)
    
    # Reverse angular dimension
    spm_flipped = reverse(spm_flipped, dims=3)
    
    # Negate tangential velocity (channel 3)
    spm_flipped[3, :, :] = -spm_flipped[3, :, :]
    
    return spm_flipped
end

"""
    rotate_action(action::Vector{Float64}, angle_deg::Float64)

Rotate action vector by given angle (in degrees).
"""
function rotate_action(action::Vector{Float64}, angle_deg::Float64)
    θ = deg2rad(angle_deg)
    R = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    return R * action
end

"""
    flip_action(action::Vector{Float64})

Flip action left-right (negate y-component).
"""
function flip_action(action::Vector{Float64})
    return [action[1], -action[2]]
end

"""
    augment_spm_transition(spm_t, action_t, spm_next; include_original=true)

Generate augmented versions of a single transition.
Returns: Vector of (spm_t, action_t, spm_next) tuples.
"""
function augment_spm_transition(spm_t::Array{Float64, 3}, 
                                action_t::Vector{Float64}, 
                                spm_next::Array{Float64, 3};
                                include_original::Bool=true)
    
    Nθ = size(spm_t, 3)
    angle_per_bin = 360.0 / Nθ
    
    augmented = []
    
    # Original
    if include_original
        push!(augmented, (copy(spm_t), copy(action_t), copy(spm_next)))
    end
    
    # Rotations (skip 0 if original is included)
    start_shift = include_original ? 1 : 0
    for shift in start_shift:(Nθ-1)
        angle = shift * angle_per_bin
        
        spm_t_rot = rotate_spm(spm_t, shift)
        action_t_rot = rotate_action(action_t, angle)
        spm_next_rot = rotate_spm(spm_next, shift)
        
        push!(augmented, (spm_t_rot, action_t_rot, spm_next_rot))
    end
    
    # Flip
    spm_t_flip = flip_spm(spm_t)
    action_t_flip = flip_action(action_t)
    spm_next_flip = flip_spm(spm_next)
    push!(augmented, (spm_t_flip, action_t_flip, spm_next_flip))
    
    # Flip + Rotations
    for shift in 1:(Nθ-1)
        angle = shift * angle_per_bin
        
        spm_t_rot = rotate_spm(spm_t_flip, shift)
        action_t_rot = rotate_action(action_t_flip, angle)
        spm_next_rot = rotate_spm(spm_next_flip, shift)
        
        push!(augmented, (spm_t_rot, action_t_rot, spm_next_rot))
    end
    
    return augmented
end

end
