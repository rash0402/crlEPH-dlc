#!/usr/bin/env python3
"""
Analyze SPM Occupancy Distribution in v7.2 Training Data

Purpose:
  Verify if 50×50 training data contains sufficient sparse SPM examples
  to generalize to 100×100 testing environment.

Outputs:
  - Occupancy statistics (mean, std, percentiles)
  - Distribution histogram
  - Sample SPMs from low/medium/high occupancy cases

Usage:
  ~/local/venv/bin/python scripts/analyze_spm_occupancy.py [--file path.h5]
"""

import h5py
import numpy as np
import sys
import os
import argparse
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from viewer.spm_reconstructor import SPMConfig, reconstruct_spm_3ch


def analyze_spm_occupancy(h5_file_path, sample_interval=10):
    """
    Analyze SPM occupancy distribution

    Args:
        h5_file_path: Path to HDF5 file
        sample_interval: Sample every N frames (default: 10 for speed)

    Returns:
        occupancy_stats: Dictionary with statistics
    """
    print(f"Analyzing: {h5_file_path}")
    print()

    # Load data
    with h5py.File(h5_file_path, 'r') as f:
        # Load trajectory
        pos_raw = np.array(f['trajectory/pos'])
        vel_raw = np.array(f['trajectory/vel'])
        heading_raw = np.array(f['trajectory/heading'])

        # Transpose to [T, N, 2] or [T, N]
        pos = np.transpose(pos_raw, (2, 1, 0))
        vel = np.transpose(vel_raw, (2, 1, 0))
        heading = np.transpose(heading_raw)

        # Load obstacles
        if 'obstacles/data' in f:
            obs_raw = np.array(f['obstacles/data'])
            if obs_raw.shape[0] > 0:
                obstacles = np.column_stack([
                    (obs_raw[:, 0] + obs_raw[:, 1]) / 2,
                    (obs_raw[:, 2] + obs_raw[:, 3]) / 2
                ])
            else:
                obstacles = np.zeros((0, 2))
        else:
            obstacles = np.zeros((0, 2))

        # Load SPM params
        spm_params = {key: f['spm_params'][key][()] for key in f['spm_params'].keys()}

        # Load metadata
        metadata = {}
        for key in f['metadata'].keys():
            val = f['metadata'][key][()]
            if isinstance(val, bytes):
                val = val.decode('utf-8')
            metadata[key] = val

    n_steps, n_agents, _ = pos.shape

    # Setup SPM config
    r_robot = float(spm_params.get('r_robot', 1.5))
    r_agent = float(spm_params.get('r_agent', 0.5))
    sensing_ratio = float(spm_params['sensing_ratio'])

    spm_config = SPMConfig(
        n_rho=int(spm_params['n_rho']),
        n_theta=int(spm_params['n_theta']),
        sensing_ratio=sensing_ratio,
        r_robot=r_robot,
        r_agent=r_agent,
        h_critical=0.0,
        h_peripheral=0.0,
        rho_index_critical=6
    )

    world_size = (
        float(metadata.get('world_width', 100.0)),
        float(metadata.get('world_height', 100.0))
    )

    print(f"Dataset info:")
    print(f"  Steps: {n_steps}, Agents: {n_agents}")
    print(f"  SPM: {spm_config.n_rho}×{spm_config.n_theta}")
    print(f"  D_max: {sensing_ratio * (r_robot + r_agent):.1f}m")
    print(f"  Sampling: every {sample_interval} frames")
    print()

    # Collect occupancy data
    occupancy_rates = []
    occupancy_ch1 = []  # Occupancy channel
    occupancy_ch2 = []  # Proximity channel
    occupancy_ch3 = []  # Risk channel

    # Sample frames
    sample_frames = range(0, n_steps, sample_interval)
    total_samples = len(sample_frames) * n_agents

    print(f"Analyzing {len(sample_frames)} frames × {n_agents} agents = {total_samples} SPMs...")

    for frame_idx, t in enumerate(sample_frames):
        if frame_idx % 50 == 0:
            progress = frame_idx / len(sample_frames) * 100
            print(f"  Progress: {progress:.1f}% ({frame_idx}/{len(sample_frames)} frames)")

        for agent_idx in range(n_agents):
            # Reconstruct SPM
            ego_pos = pos[t, agent_idx]
            ego_heading = heading[t, agent_idx]
            ego_vel = vel[t, agent_idx]
            all_pos = pos[t]
            all_vel = vel[t]

            spm = reconstruct_spm_3ch(
                ego_pos=ego_pos,
                ego_heading=ego_heading,
                all_positions=all_pos,
                all_velocities=all_vel,
                obstacles=obstacles,
                config=spm_config,
                r_agent=r_agent,
                world_size=world_size,
                ego_velocity=ego_vel
            )

            # Calculate occupancy (% of non-zero cells in each channel)
            total_cells = spm_config.n_rho * spm_config.n_theta

            occ_ch1 = np.sum(spm[:, :, 0] > 0.01) / total_cells
            occ_ch2 = np.sum(spm[:, :, 1] > 0.01) / total_cells
            occ_ch3 = np.sum(spm[:, :, 2] > 0.01) / total_cells

            # Overall occupancy (union of all channels)
            occ_any = np.sum(np.any(spm > 0.01, axis=2)) / total_cells

            occupancy_rates.append(occ_any)
            occupancy_ch1.append(occ_ch1)
            occupancy_ch2.append(occ_ch2)
            occupancy_ch3.append(occ_ch3)

    print("  Done!")
    print()

    # Convert to numpy arrays
    occupancy_rates = np.array(occupancy_rates)
    occupancy_ch1 = np.array(occupancy_ch1)
    occupancy_ch2 = np.array(occupancy_ch2)
    occupancy_ch3 = np.array(occupancy_ch3)

    # Calculate statistics
    stats = {
        'mean': np.mean(occupancy_rates),
        'std': np.std(occupancy_rates),
        'min': np.min(occupancy_rates),
        'max': np.max(occupancy_rates),
        'p10': np.percentile(occupancy_rates, 10),
        'p25': np.percentile(occupancy_rates, 25),
        'p50': np.percentile(occupancy_rates, 50),
        'p75': np.percentile(occupancy_rates, 75),
        'p90': np.percentile(occupancy_rates, 90),
        'empty_pct': np.sum(occupancy_rates < 0.05) / len(occupancy_rates) * 100,
        'sparse_pct': np.sum(occupancy_rates < 0.15) / len(occupancy_rates) * 100,
        'medium_pct': np.sum((occupancy_rates >= 0.15) & (occupancy_rates < 0.35)) / len(occupancy_rates) * 100,
        'dense_pct': np.sum(occupancy_rates >= 0.35) / len(occupancy_rates) * 100,
    }

    # Channel-specific stats
    stats['ch1_mean'] = np.mean(occupancy_ch1)
    stats['ch2_mean'] = np.mean(occupancy_ch2)
    stats['ch3_mean'] = np.mean(occupancy_ch3)

    return stats, occupancy_rates


def print_analysis_results(stats):
    """Print analysis results and interpretation"""
    print("=" * 80)
    print("SPM OCCUPANCY ANALYSIS RESULTS")
    print("=" * 80)
    print()

    print("Overall Statistics:")
    print(f"  Mean occupancy:   {stats['mean']:.3f} ({stats['mean']*100:.1f}% of cells filled)")
    print(f"  Std deviation:    {stats['std']:.3f}")
    print(f"  Min - Max:        {stats['min']:.3f} - {stats['max']:.3f}")
    print()

    print("Percentiles:")
    print(f"  10th percentile:  {stats['p10']:.3f}")
    print(f"  25th percentile:  {stats['p25']:.3f}")
    print(f"  50th (median):    {stats['p50']:.3f}")
    print(f"  75th percentile:  {stats['p75']:.3f}")
    print(f"  90th percentile:  {stats['p90']:.3f}")
    print()

    print("Distribution by Density:")
    print(f"  Empty   (<5%):    {stats['empty_pct']:.1f}%")
    print(f"  Sparse  (<15%):   {stats['sparse_pct']:.1f}%")
    print(f"  Medium  (15-35%): {stats['medium_pct']:.1f}%")
    print(f"  Dense   (>=35%):  {stats['dense_pct']:.1f}%")
    print()

    print("Channel-specific (mean occupancy):")
    print(f"  Ch1 (Occupancy):  {stats['ch1_mean']:.3f}")
    print(f"  Ch2 (Proximity):  {stats['ch2_mean']:.3f}")
    print(f"  Ch3 (Risk):       {stats['ch3_mean']:.3f}")
    print()

    print("=" * 80)
    print("INTERPRETATION & RECOMMENDATIONS")
    print("=" * 80)
    print()

    # Interpretation
    if stats['sparse_pct'] >= 40:
        print("✅ GOOD: Dataset contains significant sparse SPM examples (>40%)")
        print("   → 50×50 training data likely generalizes well to 100×100 testing")
        print()
        print("Recommendation:")
        print("  → Proceed with 50×50 training")
        print("  → Test on 100×100 and monitor VAE reconstruction error")
        print("  → If performance acceptable, no data re-collection needed")
    elif stats['sparse_pct'] >= 25:
        print("⚠️  MARGINAL: Dataset has moderate sparse coverage (25-40%)")
        print("   → Generalization to 100×100 uncertain")
        print()
        print("Recommendation:")
        print("  → Train VAE on current 50×50 data")
        print("  → Run careful 100×100 experiments with error monitoring")
        print("  → If VAE shows OOD issues, consider data augmentation or re-collection")
    else:
        print("❌ POOR: Dataset lacks sparse SPM examples (<25%)")
        print("   → High risk of distribution shift when testing on 100×100")
        print()
        print("Recommendation:")
        print("  → Re-collect data with 100×100 world size")
        print("  → Or collect additional sparse scenarios (low density)")
        print("  → Current data will likely fail on 100×100 environment")

    print()

    # Detailed analysis
    print("Detailed Analysis:")
    print()

    if stats['mean'] > 0.3:
        print(f"  • Mean occupancy ({stats['mean']:.2f}) is HIGH")
        print("    → VAE will be biased toward dense, crowded scenes")
        print("    → Sparse SPMs may be Out-of-Distribution")
    elif stats['mean'] > 0.15:
        print(f"  • Mean occupancy ({stats['mean']:.2f}) is MODERATE")
        print("    → VAE should handle medium-density scenarios")
        print("    → Very sparse scenes may still be OOD")
    else:
        print(f"  • Mean occupancy ({stats['mean']:.2f}) is LOW")
        print("    → VAE trained on sparse scenarios")
        print("    → Should generalize well to low-density environments")

    print()

    if stats['std'] > 0.15:
        print(f"  • High variance (std={stats['std']:.2f})")
        print("    → Dataset covers diverse density conditions")
        print("    → Better generalization expected")
    else:
        print(f"  • Low variance (std={stats['std']:.2f})")
        print("    → Limited diversity in SPM patterns")
        print("    → Risk of overfitting to specific density")

    print()


def main():
    parser = argparse.ArgumentParser(description="Analyze SPM Occupancy Distribution")
    parser.add_argument('--file', type=str, default=None,
                       help='Path to HDF5 file (default: use file dialog)')
    parser.add_argument('--interval', type=int, default=10,
                       help='Sample every N frames (default: 10)')
    args = parser.parse_args()

    # Get file path
    if args.file:
        h5_file = args.file
    else:
        # Use default data file
        default_file = "data/vae_training/raw_v72/v72_scramble_d10_s1_20260116_104233.h5"
        if os.path.exists(default_file):
            h5_file = default_file
        else:
            print("Error: No file specified and default file not found")
            print(f"Usage: {sys.argv[0]} --file <path.h5>")
            sys.exit(1)

    if not os.path.exists(h5_file):
        print(f"Error: File not found: {h5_file}")
        sys.exit(1)

    # Run analysis
    stats, occupancy_data = analyze_spm_occupancy(h5_file, sample_interval=args.interval)

    # Print results
    print_analysis_results(stats)

    # Save results
    output_dir = "results/spm_analysis"
    os.makedirs(output_dir, exist_ok=True)

    output_file = os.path.join(output_dir, f"occupancy_stats_{Path(h5_file).stem}.txt")
    with open(output_file, 'w') as f:
        f.write(f"SPM Occupancy Analysis\n")
        f.write(f"File: {h5_file}\n")
        f.write(f"\n")
        f.write(f"Mean: {stats['mean']:.3f}\n")
        f.write(f"Std:  {stats['std']:.3f}\n")
        f.write(f"Empty (<5%):   {stats['empty_pct']:.1f}%\n")
        f.write(f"Sparse (<15%): {stats['sparse_pct']:.1f}%\n")
        f.write(f"Medium (15-35%): {stats['medium_pct']:.1f}%\n")
        f.write(f"Dense (>=35%): {stats['dense_pct']:.1f}%\n")

    print(f"Results saved to: {output_file}")
    print()


if __name__ == "__main__":
    main()
