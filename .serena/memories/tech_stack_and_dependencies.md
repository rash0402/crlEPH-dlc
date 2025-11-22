# Tech Stack and Dependencies (Updated 2025-11-22)

## Primary Language: Julia 1.9+

### Julia Runtime
- **Installation**: Recommended via `juliaup` package manager
- **Location**: Typically `~/.juliaup/bin/julia`
- **Project activation**: `julia --project=.` in `src_julia/` directory

### Julia Dependencies (src_julia/Project.toml)

**Core Libraries:**
- **Zygote** (`e88e6eb3-aa80-5325-afca-941959d7151f`) - Automatic differentiation for gradient-based EPH controller
- **ZMQ** (`c2297ded-f4af-51ae-bb23-16f91089e4e1`) - ZeroMQ for inter-process communication (server side)
- **JSON** (`682c06a0-de6a-54ab-a142-c8b1cf79cde6`) - Message serialization for ZeroMQ protocol

**Standard Library:**
- **LinearAlgebra** - Vector/matrix operations for SPM and control
- **Random** - Agent initialization, random walk behavior
- **Statistics** - Data analysis utilities

### Installation
```bash
cd src_julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Secondary Language: Python 3.8+

### Python Runtime
- **Virtual environment**: `~/local/venv/` (configured in scripts)
- **Activation**: `source ~/local/venv/bin/activate`
- **Purpose**: Visualization only (viewer.py)

### Python Dependencies (requirements.txt)

**Visualization (Current):**
- **pygame** ≥2.5.0 - Real-time rendering (agents, FOV, haze)
- **zmq** - ZeroMQ client (SUB socket)
- **numpy** ≥1.24.0 - Array operations for visualization

**Legacy Prototype (src/ only):**
- **torch** ≥2.0.0 - PyTorch for gradient-based control (legacy)
- **matplotlib** ≥3.7.0 - Static plotting and debugging
- **scipy** ≥1.10.0 - Scientific computing utilities

**Note**: torch/matplotlib/scipy are NOT used by the production Julia simulation. They remain for legacy code analysis and comparative experiments.

### Installation
```bash
pip install -r requirements.txt
```

## Communication Protocol

### ZeroMQ (ØMQ)
- **Pattern**: PUB-SUB (Julia publishes, Python subscribes)
- **Port**: 5555 (configurable in main.jl and viewer.py)
- **Transport**: TCP (`tcp://localhost:5555`)
- **Message format**: JSON serialization

**Message schema:**
```json
{
  "frame": int,
  "agents": [{"id": int, "x": float, "y": float, "vx": float, "vy": float, "radius": float, "color": [r,g,b], "orientation": float, "has_goal": bool}],
  "haze_grid": [[float]]
}
```

## Development Tools

### Julia Ecosystem
- **Package manager**: Built-in `Pkg` (via `Project.toml`)
- **REPL**: `julia` (interactive testing)
- **Debugging**: `@show`, `@info` macros for logging

### Python Ecosystem (Legacy only)
- **Testing**: pytest, pytest-cov
- **Type checking**: mypy
- **Linting**: flake8
- **Formatting**: black, isort

**Note**: Julia code currently lacks automated testing infrastructure. Tests exist only for legacy Python code.

## System Requirements

### Ports
- **5555**: Julia ZeroMQ PUB socket (simulation server)

### Runtime Environments
- **macOS**: Primary development platform (Darwin 24.6.0)
- **Linux**: Expected to work (not regularly tested)
- **Windows**: May require ZMQ configuration adjustments

## Dependency Management Philosophy
1. **Minimal Julia deps**: Only essential packages (Zygote, ZMQ, JSON)
2. **Python for viz only**: Keep Python dependencies lightweight
3. **Lock files**: Julia `Manifest.toml` gitignored for flexibility
4. **Virtual env**: Isolate Python packages from system installation
