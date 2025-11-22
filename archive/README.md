# Archive Directory

This directory contains legacy code and implementations that are no longer actively maintained.

## Python Legacy Implementation

**Location**: `python_legacy/`

**Status**: Archived (2025-11-22)

**Migration**: Transitioned to Julia implementation in `src_julia/`

### Contents

- **`src/`**: Original Python implementation
  - `core/`: Agent, Environment, Simulator classes
  - `perception/`: NumPy-based SPM (non-differentiable)
  - `control/`: EPH and gradient-based EPH controllers
  - `utils/`: Math utilities, visualization helpers

- **`tests/`**: Pytest test suites for Python implementation
  - `test_core.py`: Core functionality tests
  - `test_spm.py`: SPM validation tests
  - `test_eph.py`: EPH controller tests
  - `test_eph_gradient.py`: Gradient EPH tests

- **`experiments/`**: Research experiment scripts
  - `heterogeneity_exp.py`: Heterogeneous agent experiments
  - `narrow_corridor_exp.py`: Narrow corridor scenarios

- **Root scripts**: Demo and debugging scripts
  - `main.py`, `main_gradient.py`: Basic demos
  - `scramble_*.py`: Scramble crossing scenarios
  - `narrow_corridor_visual.py`: Visual corridor navigation
  - `debug_*.py`: Debugging utilities
  - `visualize_spm.py`: SPM visualization tool

### Why Archived?

The Python implementation was replaced with Julia for:
1. **Performance**: 10-100× speedup for large-scale simulations
2. **Automatic differentiation**: Zygote.jl provides efficient gradient computation
3. **Type safety**: Julia's type system improves code reliability

### Use Cases

This archive is preserved for:
- **Comparative analysis**: Benchmark Julia vs Python performance
- **Reference implementation**: Cross-validate algorithms
- **Historical documentation**: Track implementation evolution
- **Educational purposes**: Learn different implementation approaches

### How to Use

To run archived Python code:

```bash
# Ensure dependencies are installed
pip install -r ../requirements.txt

# Run any script
cd python_legacy
export PYTHONPATH=..
python main.py
```

**Note**: These scripts are not maintained and may have compatibility issues with newer library versions.

## Do Not Use for Active Development

For current development, see:
- **Main implementation**: `../src_julia/`
- **Developer guide**: `../CLAUDE.md`
- **Documentation**: `../doc/`
