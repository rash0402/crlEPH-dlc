# Task Completion Guidelines (Updated 2025-11-22)

## Pre-Completion Checklist

### 1. Verify Functional Correctness

#### Julia Development
**Manual testing** (no automated tests yet):
```bash
# Run simulation and observe behavior
cd src_julia
julia --project=. main.jl
```

**Interactive REPL testing**:
```bash
cd src_julia
julia --project=.
```
```julia
# In REPL
include("Simulation.jl")
# Test individual functions interactively
```

**Visual verification**:
```bash
# Run full simulation with viewer
./scripts/run_experiment.sh
# Verify: agents move, haze renders, no crashes
```

#### Python Changes (viewer.py)
```bash
# Ensure Julia server is running first
cd src_julia && julia --project=. main.jl &

# Test viewer
export PYTHONPATH=.
python viewer.py
# Verify: rendering correct, ZeroMQ connection stable
```

### 2. Code Quality Checks

#### Julia (Manual Review)
**Type stability** (performance-critical functions):
```julia
using Zygote
@code_warntype my_function(args)
# Check for red "Any" types (indicates instability)
```

**Gradient validation** (if modifying SPM/EPH):
```julia
# Test gradient computation doesn't error
gradient(a -> cost_function(a), action)
```

**Differentiability check**:
- No in-place array operations in gradient paths
- No type instabilities in Zygote-traced functions
- No non-differentiable control flow on tracked variables

#### Python (Legacy/Viewer Only)
```bash
# Only if modifying Python code
mypy viewer.py         # Type checking
flake8 viewer.py       # Linting
black viewer.py        # Auto-format
```

### 3. Integration Testing

#### Communication Protocol
If ZeroMQ message format changed:
1. Verify Julia server sends correct JSON schema
2. Verify Python viewer parses without errors
3. Check `tech_stack_and_dependencies.md` schema matches implementation

#### Port Management
```bash
# Ensure no zombie processes
lsof -i :5555
ps aux | grep julia

# Clean up if needed
lsof -ti :5555 | xargs kill -9
```

### 4. Documentation Updates

**Always update when:**
- Changing module structure → Update `project_structure_and_architecture.md`
- Adding dependencies → Update `tech_stack_and_dependencies.md`, `Project.toml`, or `requirements.txt`
- Changing workflows → Update `suggested_commands.md`
- Modifying protocols → Update `development_guidelines_and_constraints.md`

**Consider updating:**
- `CLAUDE.md` if architecture significantly changes
- Research docs (`doc/*.md`) if theoretical framework affected

### 5. Commit Preparation

#### Stage Intentional Files Only
```bash
git status
# Review changes carefully
```

**Never stage:**
- `Manifest.toml` (Julia lock file, gitignored)
- `log/`, `tmp/` outputs
- `.DS_Store`, editor temp files
- Cache directories (`.serena/cache/`)

**Always stage:**
- Source code (`.jl`, `.py`)
- Configuration (`Project.toml`, `requirements.txt`)
- Documentation (`*.md`)
- Scripts (`scripts/*.sh`)

#### Commit Message Format
```bash
git add <files>
git commit -m "<type>: <imperative summary>

<optional body explaining why/what/how>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Type prefixes:**
- `feat:` New functionality
- `fix:` Bug fix
- `refactor:` Code restructuring (no behavior change)
- `docs:` Documentation only
- `perf:` Performance optimization
- `test:` Test additions/modifications
- `chore:` Build/dependency updates

### 6. Post-Commit Verification

```bash
# Verify clean working directory
git status

# Verify commit message formatting
git log -1

# Optionally push to remote
git push origin <branch>
```

## Task-Specific Completion Criteria

### EPH/SPM Algorithm Changes
- [ ] Gradient flow verified (no Zygote errors)
- [ ] Simulation runs without crashes for 100+ frames
- [ ] Behavior visually plausible (agents avoid collisions, follow goals)
- [ ] Mathematical justification documented in code comments
- [ ] Consistency with research docs (`doc/20251121_Emergent Perceptual Haze (EPH).md`)

### Visualization Changes
- [ ] Rendering correct (agents, FOV, haze)
- [ ] ZeroMQ connection stable (no dropped messages)
- [ ] Frame rate acceptable (30+ FPS)
- [ ] Color/sizing conventions preserved

### Parameter Tuning
- [ ] Document rationale (FEP theory, empirical testing, etc.)
- [ ] Note as provisional if lacking theoretical justification
- [ ] Consider adding to future sensitivity analysis TODO list

### Documentation Changes
- [ ] Markdown formatting correct (preview in editor)
- [ ] Code examples syntactically correct
- [ ] Cross-references valid (file paths, module names)
- [ ] Serena memories updated if project structure changed

## Common Pitfalls

### Julia
- **Mutation in gradient code** → Use `new_array = old_array .+ value` not `old_array .+= value`
- **Non-toroidal distance** → Use `wrapped_distance()` not `norm(pos1 - pos2)`
- **Hardcoded world size** → Use `env.world_size` parameter

### Python
- **ZeroMQ socket not closed** → Causes port 5555 to remain occupied
- **Wrong PYTHONPATH** → Viewer fails to import modules
- **Missing dependencies** → Activate virtual environment first

### General
- **Forgetting to update docs** → Serena memories become stale
- **Committing temp files** → Review `git status` carefully
- **Skipping manual testing** → No automated tests to catch bugs

## Emergency Procedures

### Simulation Won't Start
```bash
# Check Julia dependencies
cd src_julia
julia --project=. -e 'using Pkg; Pkg.status()'

# Reinstall if needed
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Viewer Won't Connect
```bash
# Verify server is running
lsof -i :5555

# Check Python venv
which python  # Should be ~/local/venv/bin/python

# Reinstall dependencies
pip install -r requirements.txt
```

### Port Already in Use
```bash
# Find and kill process
lsof -ti :5555 | xargs kill -9
```

### Gradient Errors
```julia
# Simplify to find breaking operation
using Zygote
gradient(x -> simple_function(x), x0)
# Incrementally add complexity until error occurs
```

## Reporting Completion

**What to report to user:**
1. Summary of changes made
2. Key files modified
3. Testing performed and results
4. Any known limitations or future work
5. How to verify/use the changes

**Example:**
> Updated EPH controller to include acceleration limits (EPH.jl:45-52). Tested with 200-frame simulation - agents now show smoother trajectories. Updated `development_guidelines_and_constraints.md` to document constraint rationale. Run `./scripts/run_experiment.sh` to verify behavior.
