# Random Obstacles Scenario Implementation

**Date**: 2026-01-14
**Status**: ✅ Core implementation complete, data generation script needs finalization

## Overview

Implemented a new **Random Obstacles** scenario for VAE training data diversity. This scenario provides unstructured environment data to complement the structured Scramble and Corridor scenarios.

---

## Implementation Summary

### 1. Core Scenario Implementation (✅ Complete)

**File**: `src/scenarios.jl`

#### Added:
- **`RANDOM_OBSTACLES`** enum value to `ScenarioType`
- **`init_random_obstacles()`** function
  - 4 groups at corners (5,5), (5,45), (45,45), (45,5)
  - Diagonal crossing paths (each group heads to opposite corner)
  - Configurable number of obstacles (default: 50)
  - Separate obstacle seed for reproducible obstacle placement
- **Random obstacle generation** in `get_obstacles()`
  - Circular obstacles with random radius (2-4m)
  - Filled with 1.0m-spaced grid points
  - 10m safe zones around agent start/goal areas
  - Independent RNG for obstacle placement
- **Updated** `ScenarioParams` struct
  - Added `num_obstacles::Union{Nothing, Int}`
  - Added `obstacle_seed::Union{Nothing, Int}`
- **Updated** `initialize_scenario()` to handle `RANDOM_OBSTACLES`

#### Key Features:
- **50×50m world** (same as Scramble for consistency)
- **Unstructured environment** (no predictable patterns)
- **Varied obstacle sizes** (2-4m radius) for realistic diversity
- **Safe zones** prevent obstacles from blocking start/goal areas
- **Reproducible** obstacle placement via `obstacle_seed`

---

### 2. Test Script (✅ Complete & Passing)

**File**: `scripts/test_obstacles_random.jl`

#### Test Results:
```
[Test 1] Basic initialization (50 obstacles, 10 agents per group)
  ✓ World size: (50.0, 50.0)
  ✓ Number of groups: 4
  ✓ Total agents: 40
  ✓ Num obstacles config: 50
  ✓ Obstacle seed: 123

[Test 2] Obstacle generation
  ✓ Total obstacle points: 511
  ✓ Estimated number of obstacle circles: ~25

[Test 3] Verify safe zones (10m radius around corners)
  ✓ No obstacles in safe zones

[Test 5] Reproducibility test
  ✓ Obstacle generation is reproducible

[Test 6] Different obstacle seeds produce different results
  ✓ Different seeds produce different obstacles
    Seed 123: 511 points
    Seed 456: 537 points

[Test 7] Varying number of obstacles
  Config: 20 obstacles → Generated 209 points
  Config: 50 obstacles → Generated 514 points
  Config: 100 obstacles → Generated 1007 points
```

All tests pass successfully!

---

### 3. Data Generation Script (⏳ Draft Created)

**File**: `scripts/create_dataset_v63_random_obstacles.jl`

#### Current Status:
- ✅ Basic structure created
- ✅ Command-line argument parsing
- ✅ Scenario initialization
- ⚠️ Needs finalization for logging (see below)

#### Configuration:
- **Densities**: 5, 10, 15, 20 agents/group
- **Obstacle counts**: 30, 50, 70 obstacles
- **Seeds**: 1-5 (5 random seeds per condition)
- **Steps**: 3000 per run
- **Controller**: Random walk + geometric collision avoidance (v6.3)
- **Target collision rate**: < 0.1%

#### Estimated Dataset:
- **Total simulations**: 60 (4 densities × 3 obstacle counts × 5 seeds)
- **Estimated time**: ~2 hours
- **Output**: `data/vae_training/raw_v63/v63_random_d{density}_n{num_obs}_s{seed}_YYYYMMDD_HHMMSS.h5`

---

## Technical Details

### Obstacle Generation Algorithm

```julia
# Pseudocode
for attempt in 1:max_attempts
    # 1. Generate random obstacle center (with 5m boundary margin)
    cx, cy = random position in [5, 45] × [5, 45]

    # 2. Generate random radius (2-4m)
    radius = 2.0 + rand() * 2.0

    # 3. Check safe zones (10m around corners)
    if distance_to_any_safe_zone(cx, cy) < safe_radius + radius:
        skip  # Too close to agent start/goal

    # 4. Fill circular obstacle with 1.0m-spaced grid points
    for x in [cx-radius : 1.0 : cx+radius]:
        for y in [cy-radius : 1.0 : cy+radius]:
            if distance(x, y, cx, cy) <= radius:
                add_obstacle_point(x, y)
end
```

### Safe Zone Logic

**Problem**: Obstacles must not block agent start/goal areas.

**Solution**: Each corner has a 10m radius safe zone. Obstacle centers are rejected if:
```
distance(obstacle_center, corner) < safe_radius + obstacle_radius
```

This ensures no part of any obstacle overlaps with the safe zone.

### Reproducibility

- **Agent seed**: Controls agent initialization (positions, IDs)
- **Obstacle seed**: Controls obstacle placement (independent of agent seed)
- Example: `seed=1, obstacle_seed=1001`

This allows generating the same agents with different obstacle layouts.

---

## Remaining Work

### Data Generation Script Finalization

The script `scripts/create_dataset_v63_random_obstacles.jl` needs the following fixes:

1. **Replace logger calls** with manual data collection
   - Use arrays to collect `pos_log`, `vel_log`, `action_log`, `heading_log`
   - Write to HDF5 at end using `h5open()`
   - Follow pattern from `scripts/create_dataset_v63_random_collision_free.jl:340-403`

2. **Add data collection loop**
   ```julia
   # Preallocate arrays
   pos_log = zeros(Float32, MAX_STEPS, n_agents, 2)
   vel_log = zeros(Float32, MAX_STEPS, n_agents, 2)
   action_log = zeros(Float32, MAX_STEPS, n_agents, 2)
   heading_log = zeros(Float32, MAX_STEPS, n_agents)

   # Collect during simulation
   for step in 1:MAX_STEPS
       for (i, agent) in enumerate(agents)
           pos_log[step, i, :] = agent.pos
           vel_log[step, i, :] = agent.vel
           action_log[step, i, :] = agent.action
           heading_log[step, i] = atan(agent.vel[2], agent.vel[1])
       end
   end
   ```

3. **Write HDF5 file** at the end
   - Follow structure from v6.3 script (lines 346-403)
   - Include metadata: density, num_obstacles, obstacle_seed

### Estimated Time to Complete

- **Effort**: ~30 minutes
- **Approach**: Copy data collection loop from `scripts/create_dataset_v63_random_collision_free.jl:270-340` and adapt

---

## Usage

### Test the Scenario

```bash
julia --project=. scripts/test_obstacles_random.jl
```

### Generate Training Data (once finalized)

```bash
# Generate all 60 simulations (densities: 5,10,15,20; obstacles: 30,50,70; seeds: 1-5)
julia --project=. scripts/create_dataset_v63_random_obstacles.jl

# Quick test (1 simulation, 100 steps)
julia --project=. scripts/create_dataset_v63_random_obstacles.jl \
  --densities=5 --obstacle-counts=30 --seeds=1:1 --dry-run

# Custom configuration
julia --project=. scripts/create_dataset_v63_random_obstacles.jl \
  --densities=10,15 --obstacle-counts=50 --seeds=1:3
```

---

## Academic Justification

### Why Random Obstacles?

**Problem**: Current VAE training data (Scramble + Corridor) is too structured.

**Risk**: VAE may overfit to specific patterns:
- Scramble: Cross-shaped agent flows
- Corridor: Linear bidirectional flow

**Solution**: Random Obstacles provides:
1. **Unstructured environment**: No predictable spatial patterns
2. **Diverse navigation**: Agents must adapt to arbitrary obstacle layouts
3. **Generalization test**: If VAE performs well here, it's truly learning general dynamics

### Dataset Composition (Proposed)

| Scenario | Structured? | Purpose |
|----------|------------|---------|
| **Scramble** | ✅ Yes | Intersection navigation (social norms) |
| **Corridor** | ✅ Yes | Constrained space navigation (bottleneck) |
| **Random Obstacles** | ❌ No | Unstructured environment (generalization) |

**Target**: ~36 files per scenario (3 scenarios × 4 densities × 3 conditions/widths/obstacles × 5 seeds) = **108 total files**

---

## Integration with VAE Training

### Current Status
- ✅ Scenario implementation complete
- ✅ Test script validates correctness
- ⏳ Data generation script needs finalization

### Next Steps
1. Finalize data generation script
2. Generate Random Obstacles dataset (60 simulations)
3. Combine with existing Scramble + Corridor data
4. Retrain VAE on full 108-file dataset
5. Evaluate generalization performance

---

## Summary

### Completed
- ✅ Random Obstacles scenario implementation
- ✅ Safe zone obstacle avoidance
- ✅ Reproducible obstacle generation
- ✅ Comprehensive test suite
- ✅ Data generation script structure

### To Do
- ⏳ Finalize data collection loop in generation script (~30 min)
- ⏳ Run full dataset generation (~2 hours)
- ⏳ Integrate with VAE training pipeline

### Files Modified
- `src/scenarios.jl`: Added Random Obstacles scenario
- `scripts/test_obstacles_random.jl`: Test script (all tests pass)
- `scripts/create_dataset_v63_random_obstacles.jl`: Data generation script (draft)

---

**Implementation Date**: 2026-01-14
**Status**: ✅ Core complete, ready for data generation
