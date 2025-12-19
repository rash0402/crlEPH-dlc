# EPH (Emergent Perceptual Haze) Project

Research implementation of the Free Energy Principle (FEP) for social robot navigation in crowded environments.

## Project Structure

```
crlEPH-dlc/
├── doc/                    # Documentation and proposals
├── src/                    # Julia source code
│   ├── config.jl          # System configuration
│   ├── spm.jl             # SPM generation
│   ├── dynamics.jl        # Agent dynamics
│   ├── controller.jl      # FEP controller
│   ├── communication.jl   # ZMQ communication
│   └── logger.jl          # HDF5 logging
├── scripts/               # Executable scripts
│   └── run_simulation.jl  # Main simulation
├── viewer/                # Python visualization
│   ├── zmq_client.py      # ZMQ subscriber
│   ├── main_viewer.py     # 4-group display
│   └── detail_viewer.py   # SPM detail view
├── Project.toml           # Julia dependencies
└── requirements.txt       # Python dependencies
```

## Quick Start

### 1. Install Dependencies

**Julia** (1.10+):
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

**Python** (3.10+):
```bash
~/local/venv/bin/pip install -r requirements.txt
```

### 2. Run Simulation

**Option A: Use launcher scripts (recommended)**

Terminal 1 - Start Julia backend:
```bash
./scripts/start_backend.fish
```

Terminal 2 - Start main viewer:
```bash
./scripts/start_main_viewer.fish
```

Terminal 3 - Start detail viewer (optional):
```bash
./scripts/start_detail_viewer.fish
```

**Option B: All-in-one launcher (macOS)**
```bash
./scripts/start_all.fish
```
This opens all 3 components in separate terminal windows.

**Option C: Manual launch**

Terminal 1:
```bash
julia --project=. scripts/run_simulation.jl
```

Terminal 2:
```bash
~/local/venv/bin/python viewer/main_viewer.py
```

Terminal 3:
```bash
~/local/venv/bin/python viewer/detail_viewer.py
```

## Features (M1 Baseline)

- **4-Group Scramble Crossing**: N/S/E/W groups in torus world
- **SPM Representation**: 16×16×3ch (Occupancy, Saliency, Risk)
- **FEP Controller**: Free energy minimization with fixed β
- **Real-time Visualization**: ZMQ-based streaming
- **HDF5 Logging**: Complete simulation data

## Next Steps (M2/M3)

- [ ] VAE world model for Haze estimation
- [ ] Adaptive β(H) modulation
- [ ] Evaluation metrics (Freezing Rate, Jerk, TTC)

## References

See `doc/EPH-proposal_all_v4.2.md` for full research proposal.
