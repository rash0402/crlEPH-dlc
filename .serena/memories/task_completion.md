# Task Completion (Quick Reference) (Updated 2025-11-22)

**See `task_completion_guidelines.md` for comprehensive checklist.**

## Quick Pre-Commit Workflow

### 1. Test Your Changes
```bash
# Julia changes
cd src_julia && julia --project=. main.jl

# Python viewer changes
./scripts/run_experiment.sh
```

### 2. Review Code Quality
**Julia (manual):**
- Check differentiability (no in-place ops in gradient paths)
- Verify toroidal geometry (use `wrapped_distance()`)
- Test gradient flow: `gradient(a -> func(a), a0)`

**Python (if modified):**
```bash
black viewer.py && flake8 viewer.py
```

### 3. Update Relevant Documentation
- Module structure → `project_structure_and_architecture.md`
- Dependencies → `tech_stack_and_dependencies.md`
- Commands → `suggested_commands.md`
- Guidelines → `development_guidelines_and_constraints.md`

### 4. Stage and Commit
```bash
git status  # Review carefully
git add <files>
git commit -m "feat: your change summary

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Never Commit
- `Manifest.toml` (Julia lock file)
- `log/`, `tmp/` directories
- `.DS_Store`, editor temp files
- `.serena/cache/`

## Common Issues

### Port 5555 Occupied
```bash
lsof -ti :5555 | xargs kill -9
```

### Dependencies Broken
```bash
# Julia
cd src_julia && julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Python
pip install -r requirements.txt
```

### Gradient Error (Julia)
Check for:
- In-place mutations (`array .+= value`)
- Type instabilities (`@code_warntype func()`)
- Non-differentiable control flow

## Testing Shortcuts

**Julia REPL:**
```bash
cd src_julia && julia --project=.
```
```julia
include("Simulation.jl")  # Load and test interactively
```

**Visual verification:**
```bash
./scripts/run_experiment.sh
# Watch for: smooth motion, haze rendering, no crashes
```

## Reference Documents
- Full guidelines: `task_completion_guidelines.md`
- Commands: `suggested_commands.md`
- Style guide: `code_style_and_conventions.md`
- Constraints: `development_guidelines_and_constraints.md`
