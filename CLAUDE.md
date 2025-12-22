# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EPH (Emergent Perceptual Haze) is a research implementation of the Free Energy Principle (FEP) for social robot navigation in crowded environments. The system uses Saliency Polar Maps (SPM) as bio-inspired perceptual representations and implements gradient-based control for collision avoidance.

## Architecture

**Julia Backend** (`src/`): Core simulation logic
- `config.jl` - System parameters (SPM, world, agent, control, communication)
- `spm.jl` - Saliency Polar Map generation (16x16x3ch: Occupancy, Saliency, Risk)
- `dynamics.jl` - Agent physics with toroidal world boundary
- `controller.jl` - FEP-based controller with free energy minimization
- `communication.jl` - ZMQ PUB socket for real-time streaming
- `logger.jl` - HDF5 data logging

**Python Viewers** (`viewer/`): Real-time visualization
- `main_viewer.py` - 4-group scramble crossing display
- `detail_viewer.py` - SPM 3-channel visualization and metrics
- `zmq_client.py` - ZMQ SUB socket client

**Entry Point**: `scripts/run_simulation.jl` - includes modules and runs main loop

## Common Commands

### Install Dependencies
```bash
# Julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Python
~/local/venv/bin/pip install -r requirements.txt
```

### Run Simulation
```bash
# Recommended: Use launcher scripts in separate terminals
./scripts/start_backend.fish      # Terminal 1: Julia backend
./scripts/start_main_viewer.fish  # Terminal 2: Main viewer
./scripts/start_detail_viewer.fish # Terminal 3: Detail viewer (optional)

# Or all-in-one (macOS)
./scripts/start_all.fish

# Manual launch
julia --project=. scripts/run_simulation.jl
~/local/venv/bin/python viewer/main_viewer.py
```

### Port Management
```bash
lsof -i :5555                    # Check if ZMQ port in use
lsof -ti :5555 | xargs kill -9   # Kill process on port
```

## Key Concepts

- **SPM (Saliency Polar Map)**: Log-polar perceptual representation mimicking primate V1 cortex
- **Toroidal World**: Agents wrap at boundaries, distances computed with wrap-around
- **Ego-centric Frame**: SPM generated relative to agent's velocity direction
- **4-Group Scramble**: N/S/E/W groups crossing at center (standard test scenario)
- **ZMQ Streaming**: Julia publishes on `tcp://127.0.0.1:5555`, Python viewers subscribe

## Configuration

Parameters are defined as structs in `src/config.jl`:
- `SPMParams` - Resolution, FOV, sensing distance, beta parameters
- `WorldParams` - World size, timestep, max steps
- `AgentParams` - Mass, damping, radius, group size
- `ControlParams` - Learning rate, safety distance, TTC threshold
- `CommParams` - ZMQ endpoint and topic names

## Data Output

- Logs saved to `log/data_YYYYMMDD_HHMMSS.h5` (HDF5 format)
- Contains SPM tensors, actions, positions, velocities per timestep
