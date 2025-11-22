# Development Guidelines and Constraints (Updated 2025-11-22)

## Top-Level Principles

### Research Alignment
- **Primary references**: `doc/20251121_Emergent Perceptual Haze (EPH).md` and `doc/20251120_Saliency Polar Map (SPM).md`
- **Developer guide**: `CLAUDE.md` for onboarding and architecture
- All implementations must align with theoretical frameworks defined in documentation

### Implementation Language Separation
- **Julia (src_julia/)**: Production simulation, performance-critical code
- **Python (viewer.py)**: Visualization only, not simulation logic
- **Legacy Python (src/)**: Reference only, do NOT modify unless explicitly requested

## Julia Development Constraints

### Differentiability Requirement
**CRITICAL**: All functions in the perception-to-action pipeline MUST support Zygote automatic differentiation.
- SPM computation (`SPM.jl`)
- EPH controller (`EPH.jl`)
- Mathematical utilities (`MathUtils.jl`)

**Prohibited patterns:**
- In-place array modifications during gradient computation
- Type instabilities (use `@code_warntype` to check)
- Non-differentiable control flow (if-else on tracked variables)

**Allowed patterns:**
- Immutable operations: `new_array = old_array .+ value`
- Soft-mapping with Gaussian kernels instead of hard binning
- Continuous sigmoid/tanh for discrete decisions

### Toroidal Geometry Mandate
All spatial computations MUST respect wrap-around boundaries:
- Distance calculations via `wrapped_distance()` in `MathUtils.jl`
- Position updates via `wrap_position()` in `MathUtils.jl`
- NEVER use naive `sqrt((x2-x1)^2 + (y2-y1)^2)` directly

### Module Structure
- Sibling modules accessed via `using ..ModuleName` (parent-relative imports)
- All modules under `src_julia/` belong to implicit parent namespace
- Keep modules focused: one concept per file (Types, SPM, EPH, etc.)

## Communication Protocol Constraints

### ZeroMQ Message Format
**Immutable contract**: JSON schema in `tech_stack_and_dependencies.md`
- Breaking changes require coordination between Julia server and Python client
- Always include `frame`, `agents`, `haze_grid` top-level keys
- Agent objects must include all fields: `id`, `x`, `y`, `vx`, `vy`, `radius`, `color`, `orientation`, `has_goal`

### Port Configuration
- **Default port**: 5555
- Check availability before starting server: `lsof -i :5555`
- Scripts must clean up ports on termination (handled in `run_experiment.sh`)

## Code Organization

### File Placement
- **Julia source**: `src_julia/` only
- **Python visualization**: Root directory (`viewer.py`) or `src/` (legacy)
- **Documentation**: `doc/` for research papers, `CLAUDE.md` for dev guide
- **Config**: Root directory (parameters inline in code, no YAML currently)
- **Transient outputs**: `log/`, `tmp/` (never commit)

### What NOT to Modify
1. **Legacy Python (src/)**: Only for reference/comparison experiments
2. **`.serena/memories/`**: Updated by Serena/Claude Code, not manually
3. **`Manifest.toml`**: Julia lock file, gitignored, regenerated automatically

## Research Integrity

### Parameter Justification
Current parameters (SPM resolution, haze decay, etc.) are **provisional**.
- Document rationale for any parameter changes
- Cite theoretical basis (FEP, Active Inference) when possible
- Mark "arbitrary choices" as TODO for future sensitivity analysis

### Baseline Comparisons (Priority P0)
Future work MUST include quantitative comparisons:
- Potential Field methods
- Ant Colony Optimization (ACO)
- Random walk baseline
Use statistical tests (t-tests, effect sizes) over 30+ trials.

### No Premature Optimization
- Maintain code clarity over micro-optimizations
- Profile before optimizing (Julia has excellent profiling tools)
- Document any performance-critical sections with `# PERFORMANCE: ...` comments

## Security & Safety

### Port Cleanup
- `run_experiment.sh` handles SIGINT (Ctrl+C) cleanup
- Never leave zombie processes on port 5555
- Check for stray Julia processes: `ps aux | grep julia`

### No Hardcoded Paths
**Prohibited:**
- Absolute paths like `/Users/username/...`
- Home directory assumptions

**Allowed:**
- Relative paths from project root
- Environment variables (e.g., `PYTHONPATH=.`)
- Dynamic path construction in scripts

### Data Privacy
- No user data collection in current simulation
- Agent trajectories/haze data may be logged for analysis but never shared externally

## Testing Philosophy

### Current State (Julia)
- **No automated tests yet** for Julia code
- Manual testing via REPL and visualization
- Future: Add unit tests for SPM, EPH, MathUtils

### Python Legacy
- Tests exist in `tests/` for legacy Python code
- Run via `pytest tests/` to verify reference implementations
- Useful for validating Julia port correctness

## Debugging Guidelines

### Julia Debugging
```julia
@show variable         # Print value during execution
@info "message" var    # Logging with context
@code_warntype func(args)  # Check type stability
```

### Gradient Issues
```julia
using Zygote
gradient(x -> f(x), x0)  # Test gradient computation
# If fails: check for in-place ops, type instabilities
```

### Communication Debugging
- **Julia side**: Add `println(json_message)` before ZMQ send
- **Python side**: Add `print(msg)` after ZMQ receive
- Verify JSON schema matches on both ends

## Git Commit Conventions

### Required Format
```
<type>: <imperative mood summary>

<optional body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Type Prefixes
- `feat:` New features or capabilities
- `fix:` Bug fixes
- `refactor:` Code restructuring without behavior change
- `docs:` Documentation updates
- `perf:` Performance improvements
- `test:` Test additions or fixes

### What to Commit
- Source code changes (`.jl`, `.py`)
- Documentation updates
- Script modifications
- Dependency updates (`Project.toml`, `requirements.txt`)

### What NOT to Commit
- `Manifest.toml` (Julia lock file)
- `log/`, `tmp/` outputs
- `.DS_Store`, editor temp files
- Virtual environment directories

## AI-DLC Expert Review Integration

### Priority-Based Development
Follow priority improvements from `doc/priority_improvements.md`:
1. **P0 (Paper essential)**: Baseline experiments, statistical validation
2. **P1 (Quality)**: Acceleration limits, convergence criteria
3. **P2 (Rigor)**: Mathematical proofs, failure mode analysis

### When Adding Features
- Check if feature addresses a P0/P1/P2 issue
- Document connection to expert recommendations
- Update `CLAUDE.md` if architecture changes
