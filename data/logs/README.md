# EPH Simulation Logs

Runtime simulation logs are stored here (git-ignored for space efficiency).

## Current Version: v7.2

**5D State Space**: Position (x, y), Velocity (vx, vy), Heading (θ)

## File Format

All logs are in HDF5 format with the following structure:

```
/trajectory/
  ├─ pos      [T, N, 2]  # Position (x, y)
  ├─ vel      [T, N, 2]  # Velocity (vx, vy)
  ├─ heading  [T, N]     # Heading θ
  ├─ u        [T, N, 2]  # Control force (Fx, Fy)
  ├─ d_goal   [N, 2]     # Direction vectors
  └─ group    [N]        # Group ID

/events/
  ├─ collision        [T, N]
  └─ near_collision   [T, N]

/obstacles/              # For random_obstacles scenario
  ├─ centers  [M, 2]
  └─ radii    [M]

/metadata/
  ├─ scenario         str
  ├─ version          str
  ├─ density          int
  ├─ seed             int
  └─ collision_rate   float

/v72_params/
  ├─ mass             float  # 70.0 kg
  ├─ k_align          float  # 4.0 rad/s
  └─ u_max            float  # 150.0 N
```

## Naming Convention

`eph_sim_YYYYMMDD_HHMMSS.h5`

Example: `eph_sim_20260118_143022.h5`

## Notes

⚠️ This directory is git-ignored (see `.gitignore`)
📊 Training data is in `data/vae_training/raw_v72/`
🔍 Use `viewer/v72/raw_viewer.py` to visualize logs
