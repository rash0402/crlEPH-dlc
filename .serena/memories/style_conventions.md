# Style & Conventions (Quick Reference) (Updated 2025-11-22)

**See `code_style_and_conventions.md` for comprehensive style guide.**

## Project Structure
- **Julia source**: `src_julia/` (core, perception, control, utils modules)
- **Python visualization**: `viewer.py` in root directory
- **Legacy Python**: `src/` (reference only, not actively developed)
- **Docs**: `doc/` for research, `CLAUDE.md` for development guide
- **Config**: Parameters inline in Julia code (no YAML currently)

## Naming Quick Reference

### Julia (Primary)
- Functions: `snake_case` - `compute_spm()`, `wrapped_distance()`
- Variables: `snake_case` - `haze_grid`, `agent_pos`
- Types: `PascalCase` - `Agent`, `Environment`
- Constants: `UPPER_SNAKE_CASE` - `MAX_SPEED`, `WORLD_SIZE`
- Modules: `PascalCase` - `SPM`, `EPH`, `Types`

### Python (Visualization)
- Functions: `snake_case` - `render_agents()`
- Variables: `snake_case` - `screen`, `clock`
- Classes: `PascalCase` - `Viewer`
- Constants: `UPPER_SNAKE_CASE` - `SCREEN_WIDTH`, `ZMQ_PORT`

## Indentation
- **Both languages**: 4 spaces (no tabs)
- **Line length**: Julia 92-120 chars, Python 88 chars (Black)

## Comments
- Docstrings for public functions (Julia: `"""..."""`, Python: `"""..."""`)
- Inline comments only for non-obvious logic
- Avoid redundant comments

## Key Conventions
- **Toroidal geometry**: Always use `wrapped_distance()`, never naive Euclidean
- **Differentiability**: No in-place mutations in gradient paths (Julia)
- **SPM channels**: `(3, nr, ntheta)` = [Occupancy, Radial Vel, Tangential Vel]
- **Coordinate systems**: World (Cartesian), Agent-relative (Polar), SPM (Log-polar)

## Formatting Tools
```bash
# Python only
black viewer.py
isort viewer.py --profile black
```

Julia lacks standard auto-formatter.

## Full Details
See `code_style_and_conventions.md` for:
- Type annotations
- Broadcasting syntax
- Module organization
- Commit message style
- Language-specific patterns
