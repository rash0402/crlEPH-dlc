# Code Style and Conventions (Updated 2025-11-22)

## Julia Style Guide (Primary)

### Indentation & Formatting
- **4 spaces** for indentation (no tabs)
- **Line length**: Soft limit at 92 characters, hard limit at 120
- **Continuation**: Align continued lines with opening delimiter

```julia
# Good
result = compute_spm(
    agent_pos, obstacles,
    nr=8, ntheta=16
)

# Avoid
result = compute_spm(agent_pos, obstacles,
nr=8, ntheta=16)
```

### Naming Conventions
- **Functions**: `snake_case` - `compute_spm()`, `wrapped_distance()`
- **Variables**: `snake_case` - `haze_grid`, `agent_pos`
- **Types/Structs**: `PascalCase` - `Agent`, `Environment`, `EPHParams`
- **Constants**: `UPPER_SNAKE_CASE` - `MAX_SPEED`, `WORLD_SIZE`
- **Modules**: `PascalCase` - `SPM`, `EPH`, `Types`, `MathUtils`

### Type Annotations
```julia
# Struct definitions: always annotate
struct Agent
    id::Int
    position::Vector{Float64}
    velocity::Vector{Float64}
    radius::Float64
end

# Function arguments: annotate for clarity, not required
function compute_distance(pos1::Vector{Float64}, pos2::Vector{Float64})::Float64
    # ...
end

# Internal variables: rarely annotate (Julia infers)
distance = compute_distance(agent.position, obstacle_pos)
```

### Comments
- **Docstrings**: Use `"""triple quotes"""` for public functions
```julia
"""
    compute_spm(agent_pos, obstacles; nr=8, ntheta=16)

Compute Saliency Polar Map using log-polar binning.

# Arguments
- `agent_pos::Vector{Float64}`: Agent position [x, y]
- `obstacles::Vector{Agent}`: List of nearby obstacles

# Returns
- `spm::Array{Float64, 3}`: SPM tensor (3, nr, ntheta)
"""
function compute_spm(agent_pos, obstacles; nr=8, ntheta=16)
    # ...
end
```

- **Inline comments**: For non-obvious math or algorithms only
```julia
# Use sigmoid to create soft attention mask (differentiable)
attention = sigmoid.((distances .- personal_space) ./ bandwidth)
```

- **Avoid redundant comments**
```julia
# Bad: redundant
x = x + 1  # Increment x

# Good: explains why
x = x + 1  # Frame counter for ZeroMQ timestamp
```

### Broadcasting
Use `.` notation for element-wise operations (cleaner and faster):
```julia
# Good
result = sin.(angles) .* weights

# Avoid (unless you want to manually broadcast)
result = [sin(θ) * w for (θ, w) in zip(angles, weights)]
```

### Array Indexing
- **1-based indexing** (Julia convention)
- Use `begin` and `end` keywords for first/last elements
```julia
first_element = array[begin]
last_element = array[end]
second_to_last = array[end-1]
```

### Mutating Functions
Append `!` to functions that modify arguments in-place:
```julia
function update_agent!(agent::Agent, new_velocity)
    agent.velocity = new_velocity
end
```

**Note**: Avoid mutations in Zygote-differentiated code paths!

### Module Organization
```julia
module MyModule

using LinearAlgebra
using ..Types  # Sibling module

export public_function, PublicStruct

# Implementation...

end  # module
```

## Python Style Guide (Visualization Only)

### Indentation & Formatting
- **4 spaces** for indentation (PEP 8)
- **Line length**: 88 characters (Black formatter default)
- **Blank lines**: 2 before top-level functions/classes, 1 inside classes

### Naming Conventions (PEP 8)
- **Functions/methods**: `snake_case` - `render_agents()`, `connect_zmq()`
- **Variables**: `snake_case` - `agent_data`, `haze_grid`
- **Classes**: `PascalCase` - `Viewer`, `AgentRenderer`
- **Constants**: `UPPER_SNAKE_CASE` - `SCREEN_WIDTH`, `ZMQ_PORT`
- **Modules**: `lowercase` or `snake_case` - `viewer.py`, `math_utils.py`

### Type Hints (Python 3.8+)
```python
from typing import List, Dict, Tuple

def render_agents(
    screen: pygame.Surface,
    agents: List[Dict[str, float]],
    scale: float = 1.0
) -> None:
    """Render agents on Pygame surface."""
    # ...
```

### Docstrings (Google Style)
```python
def parse_message(msg_json: str) -> Dict:
    """Parse ZeroMQ JSON message into agent data.

    Args:
        msg_json: Raw JSON string from ZeroMQ socket

    Returns:
        Dictionary with 'frame', 'agents', 'haze_grid' keys

    Raises:
        ValueError: If JSON is malformed
    """
    # ...
```

### Formatting Tools
Run before committing:
```bash
black viewer.py          # Auto-format
isort viewer.py --profile black  # Sort imports
```

## Language-Specific Design Patterns

### Julia: Differentiable Code
**Golden rule**: Avoid mutations in gradient computation paths
```julia
# Good (immutable)
new_spm = spm .+ haze_noise

# Bad (in-place, breaks Zygote)
spm .+= haze_noise
```

### Julia: Performance
```julia
# Type stability check
@code_warntype my_function(args)

# Profiling
using Profile
@profile my_function(args)
Profile.print()
```

### Python: ZeroMQ Pattern
```python
import zmq

context = zmq.Context()
socket = context.socket(zmq.SUB)
socket.connect("tcp://localhost:5555")
socket.setsockopt_string(zmq.SUBSCRIBE, "")

while True:
    msg = socket.recv_string()
    data = json.loads(msg)
    # Process data...
```

## File Headers

### Julia Files
```julia
# Filename: SPM.jl
# Purpose: Saliency Polar Map computation with Gaussian splatting
# Dependencies: LinearAlgebra, ..Types

module SPM

# ...

end  # module SPM
```

### Python Files
```python
"""
Filename: viewer.py
Purpose: Real-time Pygame visualization for EPH simulation
Dependencies: pygame, zmq, numpy
"""

import pygame
import zmq
# ...
```

## Commit Message Style

See `development_guidelines_and_constraints.md` for full conventions.

**Quick reference:**
```
feat: add haze grid rendering to viewer
fix: correct toroidal distance calculation in MathUtils
refactor: simplify SPM Gaussian splatting logic
docs: update CLAUDE.md with Julia setup instructions
perf: optimize SPM binning loop

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Project-Specific Conventions

### SPM Channel Ordering
Always use `(3, nr, ntheta)` with channels:
1. **Channel 1**: Occupancy (0.0 = free, 1.0 = obstacle)
2. **Channel 2**: Radial velocity (+ approaching, - receding)
3. **Channel 3**: Tangential velocity (+ left-to-right, - right-to-left)

### Coordinate Systems
- **World**: Cartesian (x, y), origin at (0, 0), toroidal wrap-around
- **Agent-relative**: Polar (r, θ), θ=0 is agent's forward direction
- **SPM**: Log-polar bins, bin 0 = personal space, bins 1+ = log-spaced

### Parameter Naming
Use descriptive names, avoid single-letter except for math:
```julia
# Good
personal_space = 2.0
max_perception_range = 50.0

# Acceptable for math formulas
r = sqrt(dx^2 + dy^2)
θ = atan(dy, dx)

# Avoid in general code
ps = 2.0  # What is ps?
```

## When to Deviate

These guidelines are **strong recommendations**, not absolute rules.

**Acceptable deviations:**
- Math-heavy code: Use mathematical notation (α, β, λ) in comments for clarity
- Performance-critical sections: Prioritize speed over style (document with `# PERFORMANCE:`)
- Legacy compatibility: When interfacing with `src/` Python code

**Document deviations:**
```julia
# DEVIATION: Using 1-letter vars for matrix ops (matches math paper notation)
A = [1 2; 3 4]
x = [1, 0]
b = A * x
```
