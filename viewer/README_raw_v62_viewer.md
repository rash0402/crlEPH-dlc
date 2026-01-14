# Raw V6.2 Trajectory Viewer

Interactive visualization tool for EPH raw trajectory data (HDF5 format).

## Features

### 1. Global Map
- Displays all agent positions in world coordinates
- Interactive agent selection (click to select)
- Real-time position updates with time slider
- Obstacle visualization

### 2. Local View (Agent-Centered)
- Ego-centric view of selected agent
- Sensing range circle (configurable)
- Other agents within sensing range
- Coordinate frame aligned with ego heading

### 3. SPM Visualization (3 Channels)
- **Channel 1 (Occupancy)**: Binary occupancy map
- **Channel 2 (Proximity Saliency)**: Inverse distance weighting
- **Channel 3 (Collision Hazard)**: CH2 + CH3 (TTC-based)

### 4. SPM Prediction (Placeholder)
- VAE-based prediction (to be implemented)
- Requires trained VAE model

### 5. Agent Info Panel
- Position (x, y)
- Velocity (vx, vy, |v|)
- Control input (v, ω)
- Heading angle

### 6. Playback Controls
- **Time Slider**: Navigate through trajectory
- **Play/Pause Button**: Automatic playback (20 FPS)
- **Reset Button**: Return to start

## Usage

### Method 1: Convenience Scripts (Recommended)

Use the provided launch scripts in `scripts/`:

```bash
# GUI file selector (easiest)
./scripts/view_raw_v62.sh

# Quick select by scenario
./scripts/view_raw_v62.sh scramble d10 s1
./scripts/view_raw_v62.sh corridor w40 d15 s3

# Specific file path
./scripts/view_raw_v62.sh data/vae_training/raw_v62/v62_scramble_d10_s1_20260112_192928.h5
```

Or use the Python script:

```bash
python scripts/view_raw_v62.py                    # GUI file selector
python scripts/view_raw_v62.py scramble d10 s1    # Quick select
python scripts/view_raw_v62.py corridor w40 d15 s3 # Quick select corridor
```

### Method 2: Direct Viewer Launch

#### GUI File Selection

Simply run without arguments to open a file selector dialog:

```bash
cd /Users/igarashi/local/project_workspace/crlEPH-dlc
python viewer/raw_v62_viewer.py
```

The dialog will open in `data/vae_training/raw_v62/` by default, where all 80 trajectory files are located.

#### Command-Line File Specification

You can also specify a file directly:

```bash
# Relative path
python viewer/raw_v62_viewer.py data/vae_training/raw_v62/v62_scramble_d10_s1_20260112_192928.h5

# Absolute path
python viewer/raw_v62_viewer.py /full/path/to/trajectory.h5
```

#### Using Default File (No GUI)

To disable GUI file selector and use the default file:

```bash
python viewer/raw_v62_viewer.py --no-gui
```

### Interactive Controls

1. **Select Agent**: Click on any agent in the global map
2. **Open File**: Click "Open File" button to load a different trajectory
3. **Playback**: Use Play/Pause button or time slider
4. **Reset**: Reset to beginning of trajectory
5. **Zoom/Pan**: Use matplotlib toolbar (bottom left)

## HDF5 Data Structure

The viewer expects HDF5 files with the following structure:

```
/
├── trajectory/
│   ├── pos [2, N_agents, N_steps]     # Position (x, y)
│   ├── vel [2, N_agents, N_steps]     # Velocity (vx, vy)
│   ├── u [2, N_agents, N_steps]       # Control (v, ω)
│   └── heading [N_agents, N_steps]    # Heading angle
├── obstacles/
│   └── data [2, N_obstacles]          # Obstacle positions
├── metadata/
│   ├── scenario
│   ├── density
│   ├── n_agents
│   ├── n_steps
│   └── ...
└── spm_params/
    ├── n_rho
    ├── n_theta
    ├── sensing_ratio
    ├── h_critical
    ├── h_peripheral
    └── rho_index_critical
```

## Implementation Details

### SPM Reconstruction

SPMs are reconstructed on-the-fly using Python implementation (`spm_reconstructor.py`):

- **Log-polar binning**: 16 radial × 16 angular bins (configurable)
- **Sensing range**: 7.5 × (r_robot + r_agent) = 22.5m (default)
- **Coordinate transform**: Ego-centric with heading alignment

### Performance

- **Data loading**: <1s for typical file (~2MB)
- **SPM reconstruction**: ~50ms per frame (Python)
- **Playback**: 20 FPS (50ms update interval)

## Dependencies

- Python 3.8+
- numpy
- matplotlib
- h5py

Install via:

```bash
pip install numpy matplotlib h5py
```

## Files

- `raw_v62_viewer.py`: Main viewer application
- `spm_reconstructor.py`: SPM reconstruction module
- `README_raw_v62_viewer.md`: This documentation

## Troubleshooting

### Issue: "File not found"

**Solution**: Verify HDF5 file path. Use absolute path if needed:

```bash
python viewer/raw_v62_viewer.py /full/path/to/file.h5
```

### Issue: SPM appears empty

**Solution**: Check if agents are within sensing range. Try different timesteps or agents.

### Issue: Slow playback

**Solution**: SPM reconstruction is CPU-intensive. Reduce update frequency or use smaller scenarios.

## Future Enhancements

- [ ] VAE prediction integration (load trained models)
- [ ] Export functionality (video, images)
- [ ] Trajectory history trails
- [ ] Multiple agent selection
- [ ] Heatmap overlays (Precision, Free Energy)
- [ ] Side-by-side comparison (multiple files)

## Example Screenshots

### Scramble Scenario (Density 10)
```
Global Map: 40 agents crossing in 4 groups
Local View: Selected agent with 8 neighbors in range
SPM: High occupancy in front (Ch1), collision risk on sides (Ch3)
```

### Corridor Scenario (Width 40m, Density 15)
```
Global Map: Bi-directional flow
Local View: Selected agent in crowded corridor
SPM: Linear occupancy pattern (Ch1), high proximity (Ch2)
```

## Citation

If you use this viewer in your research, please cite:

```
@software{eph_raw_v62_viewer,
  title={Raw V6.2 Trajectory Viewer for EPH},
  author={EPH Development Team},
  year={2026},
  url={https://github.com/yourusername/crlEPH-dlc}
}
```

## License

MIT License (see repository root)

## Contact

For bug reports or feature requests, please open an issue on GitHub.
