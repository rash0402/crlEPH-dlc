module MathUtils

export normalize_angle, toroidal_distance, toroidal_diff

"""
    normalize_angle(angle)

Normalize angle to be within [-π, π].
"""
function normalize_angle(angle::Float64)
    return (angle + π) % (2π) - π
end

"""
    toroidal_diff(pos1, pos2, w, h)

Calculate (dx, dy) from pos1 to pos2 in a toroidal world.
"""
function toroidal_diff(pos1::Vector{Float64}, pos2::Vector{Float64}, w::Float64, h::Float64)
    dx = pos2[1] - pos1[1]
    dy = pos2[2] - pos1[2]
    
    if dx > w / 2
        dx -= w
    elseif dx < -w / 2
        dx += w
    end
    
    if dy > h / 2
        dy -= h
    elseif dy < -h / 2
        dy += h
    end
    
    return dx, dy
end

"""
    toroidal_distance(pos1, pos2, w, h)

Calculate distance and (dx, dy) in a toroidal world.
"""
function toroidal_distance(pos1::Vector{Float64}, pos2::Vector{Float64}, w::Float64, h::Float64)
    dx, dy = toroidal_diff(pos1, pos2, w, h)
    dist = sqrt(dx^2 + dy^2)
    return dx, dy, dist
end

end
