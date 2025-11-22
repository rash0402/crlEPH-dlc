# Suggested Commands (Updated 2025-11-22)

## Primary Workflow (Julia + Python)

### Run Full Simulation
```bash
./scripts/run_experiment.sh
```
Starts Julia server (port 5555) and Python viewer simultaneously. Handles cleanup on Ctrl+C.

**Prerequisites:**
- Julia installed via juliaup (`~/.juliaup/bin/julia`)
- Python venv at `~/local/venv/`
- Port 5555 available

## Julia Development

### Run Simulation Server
```bash
cd src_julia
julia --project=. main.jl
```
Starts ZeroMQ PUB server on port 5555. Runs EPH simulation without visualization.

### Install/Update Julia Dependencies
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```
Installs packages from `Project.toml` into project-local environment.

### Julia REPL for Interactive Testing
```bash
cd src_julia
julia --project=.
```
Then inside REPL:
```julia
include("main.jl")  # Load modules
# Test individual functions interactively
```

### Add Julia Package
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.add("PackageName")'
```

## Python Visualization

### Run Viewer (requires Julia server running)
```bash
export PYTHONPATH=.
python viewer.py
```
Connects to `tcp://localhost:5555` and renders simulation in Pygame window.

### Activate Python Virtual Environment
```bash
source ~/local/venv/bin/activate
```

### Install/Update Python Dependencies
```bash
pip install -r requirements.txt
```

## Legacy Python Experiments (src/)

**Note**: These are legacy prototypes. Active development is in Julia.

### Scramble Crossing with SPM
```bash
python scramble_with_spm.py
```

### Narrow Corridor Visualization
```bash
python narrow_corridor_visual.py
```

### Debug Scripts
```bash
python debug_gradient.py          # Test gradient flow
python debug_collision.py         # Verify collision detection
python debug_inside_obstacle.py   # Check SPM occupancy mapping
python visualize_spm.py           # Visualize SPM tensor structure
```

## Code Quality (Python only - Julia lacks tooling)

### Run Python Tests
```bash
python -m pytest tests/ -v
python -m pytest -m "not slow" --maxfail=1  # Skip slow tests
```

### Python Type Checking & Linting
```bash
mypy src             # Type checking
flake8 src           # Style linting
black src            # Auto-format
isort src --profile black  # Sort imports
```

## Search & Navigation

### Fast Pattern Search
```bash
rg <pattern>         # Search codebase
rg --files           # List all files
rg "EPH" --type jl   # Search Julia files only
```

### Directory Listing
```bash
tree -L 2 src_julia/  # Show Julia module structure
ls -la .serena/       # Check Serena memories
```

## Git Workflow

### Check Status
```bash
git status
git diff
git log --oneline -10
```

### Commit with Conventional Prefix
```bash
git add <files>
git commit -m "feat: add gradient-based action selection

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Port Management

### Check if Port 5555 is in Use
```bash
lsof -i :5555
```

### Kill Process on Port 5555
```bash
lsof -ti :5555 | xargs kill -9
```

## Project Maintenance

### Clean Temporary Files
```bash
rm -rf log/* tmp/*
```

### Update Serena Memories (via Claude Code)
Ask Claude Code to review and update `.serena/memories/` when project structure changes significantly.
