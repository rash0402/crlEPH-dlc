# Suggested Commands (Updated 2026-01-09)

## Quick Start

### Full System Launch (Recommended)
```bash
./scripts/run_all.sh
```
Starts Julia backend + Main viewer + Detail viewer simultaneously. Handles cleanup on Ctrl+C.

**Prerequisites:**
- Julia 1.10+ installed
- Python venv at `~/local/venv/`
- Port 5555 available

## Simulation Workflows

### Run Simulation (Backend Only)
```bash
julia --project=. scripts/run_simulation.jl
```
Runs EPH simulation with ZMQ streaming on port 5555. No visualization.

### Run with Viewers (Manual)
```bash
# Terminal 1: Julia backend
julia --project=. scripts/run_simulation.jl

# Terminal 2: Main viewer (4-group color display)
~/local/venv/bin/python viewer/main_viewer.py

# Terminal 3: Detail viewer (SPM + metrics)
~/local/venv/bin/python viewer/detail_viewer.py
```

## VAE Training & Validation

### Collect Training Data
```bash
julia --project=. scripts/collect_diverse_vae_data.jl
```
Generates diverse SPM-action-nextSPM triplets for VAE training.
- Output: `data/vae_training/*.csv`
- Duration: ~10-20 minutes for sufficient data

### Train Action VAE (Pattern D)
```bash
julia --project=. scripts/train_action_vae.jl
```
Trains Action-Conditioned VAE with counterfactual Haze.
- Encoder: (y, u) → q(z|y,u)
- Decoder: (z, u) → ŷ
- Saves checkpoints to `models/action_vae_epoch_N.bson`
- Best model: `models/action_vae_best.bson`

### Validate Haze Correlation
```bash
julia --project=. scripts/validate_haze.jl
```
Validates that Haze correlates with action risk.
- Generates plots: `results/haze_validation/`
- Tests: Safe vs Risky actions → Low vs High Haze

## Evaluation & Metrics

### Run Metrics Evaluation
```bash
julia --project=. scripts/evaluate_metrics.jl
```
Computes evaluation metrics from simulation logs:
- Success Rate, Collision Rate, Freezing Rate
- Jerk (smoothness), min TTC (safety)
- Ablation study: A1-A4 conditions

### M4 Milestone Validation
```bash
julia --project=. scripts/validate_m4.jl
```
Validates M4 features (EFE, Ch3-centric, Swarm).

## Julia Development

### Interactive REPL
```bash
julia --project=.
```
Then inside REPL:
```julia
include("scripts/run_simulation.jl")  # Load modules
using .SPM, .Config, .ActionVAE       # Import specific modules

# Test individual functions
config = init_spm()
# ... interactive experimentation
```

### Install/Update Julia Dependencies
```bash
# First-time setup
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Update all packages
julia --project=. -e 'using Pkg; Pkg.update()'

# Add new package
julia --project=. -e 'using Pkg; Pkg.add("PackageName")'

# Check package status
julia --project=. -e 'using Pkg; Pkg.status()'
```

### Precompile (Speed up startup)
```bash
julia --project=. -e 'using Pkg; Pkg.precompile()'
```

## Python Visualization

### Activate Virtual Environment
```bash
source ~/local/venv/bin/activate
```

### Install/Update Python Dependencies
```bash
pip install -r requirements.txt

# Update specific package
pip install --upgrade pygame matplotlib
```

### Run Viewers Individually
```bash
# Main viewer (requires Julia backend running)
~/local/venv/bin/python viewer/main_viewer.py

# Detail viewer (requires Julia backend running)
~/local/venv/bin/python viewer/detail_viewer.py
```

## Data Management

### List Simulation Logs
```bash
ls -lh data/logs/
```

### Inspect HDF5 Log
```bash
# Via Python
python3 -c "
import h5py
f = h5py.File('data/logs/eph_sim_YYYYMMDD_HHMMSS.h5', 'r')
print(list(f['data'].keys()))
print('SPM shape:', f['data/spm'].shape)
"
```

### Clean Generated Data
```bash
# Remove logs (keep VAE models)
rm -rf data/logs/*

# Remove all generated data (careful!)
rm -rf data/logs/* results/*/

# Remove VAE checkpoints (can regenerate)
rm -rf models/action_vae_epoch_*.bson
```

## Port & Process Management

### Check Port 5555 Status
```bash
lsof -i :5555
```

### Kill Process on Port 5555
```bash
lsof -ti :5555 | xargs kill -9
```

### Kill All Julia Processes (Emergency)
```bash
killall julia
```

## Code Quality & Search

### Fast Pattern Search (ripgrep)
```bash
rg "pattern"                    # Search all files
rg "Action.*VAE" --type jl      # Search Julia files only
rg "Haze" src/                  # Search in specific directory
rg --files | grep ".jl"         # List all Julia files
```

### Directory Tree
```bash
tree -L 2 -I '__pycache__|*.pyc|.git|*.bson|*.h5'
tree src/                       # Julia source structure
tree viewer/                    # Python viewers
```

### Find Files
```bash
find . -name "*.jl" -type f     # All Julia files
find src/ -name "*vae*"         # VAE-related files
```

## Git Workflow

### Check Status
```bash
git status
git diff                        # Unstaged changes
git diff --staged              # Staged changes
git log --oneline -10          # Recent commits
```

### Stage & Commit
```bash
git add <files>
git commit -m "feat: add counterfactual Haze estimation

Implemented Pattern D encoder with action-dependent latent distribution.
Haze now reflects 'what-if' uncertainty for proposed actions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### View Changes
```bash
git diff src/action_vae.jl     # Changes in specific file
git show HEAD                   # Last commit details
```

## Debugging

### Julia Debugging
```bash
# Run with debug output
JULIA_DEBUG=all julia --project=. scripts/run_simulation.jl

# Check compilation issues
julia --project=. --check-bounds=yes scripts/run_simulation.jl

# Profile performance
julia --project=. -e '
using Profile
include("scripts/run_simulation.jl")
@profile main()
Profile.print()
'
```

### ZMQ Debugging
```bash
# Monitor ZMQ messages (requires zmq-tools)
zmqc SUB tcp://127.0.0.1:5555 ""

# Test ZMQ connectivity
python3 -c "
import zmq
ctx = zmq.Context()
sock = ctx.socket(zmq.SUB)
sock.connect('tcp://127.0.0.1:5555')
sock.subscribe(b'')
print('Connected to ZMQ')
"
```

### Log Analysis
```bash
# Tail Julia stdout
tail -f /tmp/julia_sim.log

# Search for errors
grep -i error data/logs/*.log

# Count Freezing events
grep "Freezing detected" data/logs/*.log | wc -l
```

## Performance Profiling

### Measure Simulation Speed
```bash
# Add timing to run_simulation.jl
julia --project=. -e '
using BenchmarkTools
include("scripts/run_simulation.jl")
@time main()  # Single run
@benchmark main() samples=10  # Multiple runs
'
```

### Memory Profiling
```bash
julia --project=. --track-allocation=user scripts/run_simulation.jl
# Generates *.mem files showing allocation hotspots
```

## Experiments & Reproducibility

### Run with Fixed Random Seed
```bash
julia --project=. -e '
using Random
Random.seed!(42)
include("scripts/run_simulation.jl")
main()
'
```

### Batch Experiments (30 trials)
```bash
for i in {1..30}; do
  echo "Trial $i"
  julia --project=. scripts/run_simulation.jl --seed=$i
done
```

### Parameter Sweep
```bash
# Sweep beta range
for beta_max in 1.0 5.0 10.0 20.0; do
  julia --project=. scripts/run_simulation.jl --beta-max=$beta_max
done
```

## Documentation

### Update Serena Memories
Ask Claude Code to review and update `.serena/memories/` when:
- Project structure changes significantly
- New modules/features added
- Architecture decisions made

### Generate Documentation (Future)
```bash
# Julia docstrings → Markdown (via Documenter.jl)
julia --project=. docs/make.jl
```

## Troubleshooting

### Julia Package Issues
```bash
# Clear compiled cache
rm -rf ~/.julia/compiled

# Reset package state
julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.gc()'

# Reinstall from scratch
rm -f Manifest.toml
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Python Import Errors
```bash
# Check Python path
python3 -c "import sys; print(sys.path)"

# Verify package installation
pip list | grep pygame

# Reinstall problematic package
pip install --force-reinstall pygame
```

### Viewer Window Not Showing
```bash
# Check DISPLAY variable (Linux)
echo $DISPLAY

# Try headless mode (future feature)
PYGAME_HIDE_SUPPORT_PROMPT=1 python viewer/main_viewer.py --headless
```

## Maintenance

### Clean Build Artifacts
```bash
# Julia compiled cache
rm -rf ~/.julia/compiled/v1.10/

# Python bytecode
find . -type d -name __pycache__ -exec rm -rf {} +
find . -type f -name "*.pyc" -delete
```

### Disk Usage Analysis
```bash
du -sh data/ models/ results/
du -sh ~/.julia/packages/  # Julia package storage
```

### Update All Dependencies
```bash
# Julia
julia --project=. -e 'using Pkg; Pkg.update()'

# Python
pip install --upgrade -r requirements.txt
```
