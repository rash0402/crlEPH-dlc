# EPH Setup Guide

## Quick Setup (Automated)

**Recommended**: Use the automated setup script:

```bash
./scripts/setup.sh
```

This script will:
1. Check Julia 1.10+ installation
2. Install Julia dependencies (`Pkg.instantiate()`)
3. Check/create Python virtual environment
4. Install Python dependencies
5. Verify installation

**First-time setup takes ~5-10 minutes** (downloading and compiling packages).

---

## Manual Setup

If you prefer manual setup or encounter issues with the automated script:

### Prerequisites

#### Julia Installation

Julia 1.10+ is required. Install via:

**Option 1: juliaup (Recommended)**
```bash
curl -fsSL https://install.julialang.org | sh
```

**Option 2: Homebrew**
```bash
brew install julia
```

**Option 3: Official Download**
- Visit https://julialang.org/downloads/

After installation, verify:
```bash
julia --version  # Should show 1.10.0 or higher
```

#### Python Environment

Python 3.10+ is required. Create virtual environment:

```bash
mkdir -p ~/local
python3 -m venv ~/local/venv
source ~/local/venv/bin/activate
```

### Installation Steps

#### 1. Install Julia Dependencies

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

This will install:
- **Flux.jl** - Neural network framework (VAE)
- **Zygote.jl** - Automatic differentiation (VAE training)
- **ForwardDiff.jl** - Forward-mode AD (action gradient)
- **HDF5.jl** - Data logging
- **ZMQ.jl** - Inter-process communication
- **MsgPack.jl** - Binary serialization
- **BSON.jl** - Model serialization

**First run takes ~5 minutes** (downloading and precompiling).

#### 2. Install Python Dependencies

```bash
~/local/venv/bin/pip install -r requirements.txt
```

Already completed ✅

## Running the Simulation

### Terminal 1: Julia Backend

```bash
cd /Users/igarashi/local/project_workspace/crlEPH-dlc
julia --project=. scripts/run_simulation.jl
```

Expected output:
```
============================================================
EPH Simulation - M1 Baseline (Fixed β)
============================================================

📋 Configuration:
  SPM: 16x16, FOV=210.0°
  Agents: 10 per group (4 groups)
  ...
```

### Terminal 2: Main Viewer (Python)

```bash
cd /Users/igarashi/local/project_workspace/crlEPH-dlc
~/local/venv/bin/python viewer/main_viewer.py
```

Shows 4-group scramble crossing with color-coded agents.

### Terminal 3: Detail Viewer (Optional)

```bash
cd /Users/igarashi/local/project_workspace/crlEPH-dlc
~/local/venv/bin/python viewer/detail_viewer.py
```

Shows SPM 3-channel visualization and metrics for Agent 1.

## Troubleshooting

### Julia Not Found

If `julia` command is not found, add to PATH:

```bash
# For juliaup installation:
echo 'export PATH="$HOME/.juliaup/bin:$PATH"' >> ~/.config/fish/config.fish

# For Homebrew installation:
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.config/fish/config.fish
```

### ZMQ Connection Issues

If viewers can't connect:
1. Ensure Julia backend is running first
2. Check endpoint in `src/config.jl` (default: `tcp://127.0.0.1:5555`)
3. Verify no firewall blocking localhost connections

### HDF5 Errors

If HDF5.jl fails to install:
```bash
brew install hdf5
```

Then reinstall Julia packages.

## Next Steps

Once simulation runs successfully:
1. Verify 4-group agents move in expected directions (N↓, S↑, E→, W←)
2. Check SPM visualization shows occupancy, saliency, and risk channels
3. Confirm HDF5 file is created with simulation data
4. Proceed to M2 (VAE implementation)
