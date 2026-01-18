#!/usr/bin/env python3

"""
SPM Spatial Distribution Analysis Tool

Analyzes how Haze affects SPM spatial characteristics and relates to Free Energy
"""

import h5py
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from pathlib import Path
import sys

def load_simulation_data(filepath):
    """Load SPM and diagnostic data from HDF5"""
    with h5py.File(filepath, 'r') as f:
        data = {
            'spms': f['spms'][:],                    # (n_steps, n_agents, 16, 16, 3)
            'spm_statistics': f['spm_statistics'][:], # (n_steps, n_agents, 11)
            'free_energies': f['free_energies'][:],   # (n_steps, n_agents, 4)
            'betas': f['betas'][:],                   # (n_steps, n_agents, 2)
            'precisions': f['precisions'][:],         # (n_steps, n_agents)
            'actions': f['actions'][:],               # (n_steps, n_agents, 2)
            'haze': f.attrs['haze_fixed']
        }
    return data

def compute_spatial_regions(spm_3ch):
    """
    Divide SPM into spatial regions and compute statistics

    Args:
        spm_3ch: (16, 16, 3) SPM array

    Returns:
        dict with region statistics
    """
    n_rho, n_theta, _ = spm_3ch.shape

    # Define regions (rho: radial, theta: angular)
    # Inner (close): rho 0-7, Outer (far): rho 8-15
    # Front: theta 4-11 (center ±3 cells), Side: theta 0-3 & 12-15

    regions = {}

    for ch_idx, ch_name in enumerate(['Occupancy', 'Proximity', 'Collision']):
        ch = spm_3ch[:, :, ch_idx]

        # Radial regions
        inner = ch[0:8, :]
        outer = ch[8:16, :]

        # Angular regions (assuming center is around theta=8)
        front = ch[:, 4:12]
        side = np.concatenate([ch[:, 0:4], ch[:, 12:16]], axis=1)

        # Combined regions
        inner_front = ch[0:8, 4:12]
        inner_side = np.concatenate([ch[0:8, 0:4], ch[0:8, 12:16]], axis=1)
        outer_front = ch[8:16, 4:12]
        outer_side = np.concatenate([ch[8:16, 0:4], ch[8:16, 12:16]], axis=1)

        regions[ch_name] = {
            'global_mean': np.mean(ch),
            'global_std': np.std(ch),
            'global_var': np.var(ch),
            'inner_mean': np.mean(inner),
            'inner_var': np.var(inner),
            'outer_mean': np.mean(outer),
            'outer_var': np.var(outer),
            'front_mean': np.mean(front),
            'front_var': np.var(front),
            'side_mean': np.mean(side),
            'side_var': np.var(side),
            'inner_front_mean': np.mean(inner_front),
            'inner_side_mean': np.mean(inner_side),
            'outer_front_mean': np.mean(outer_front),
            'outer_side_mean': np.mean(outer_side),
            'radial_gradient': np.mean(outer) - np.mean(inner),
            'angular_gradient': np.mean(front) - np.mean(side)
        }

    return regions

def analyze_time_averaged_spm(data):
    """Compute time and agent-averaged SPM characteristics"""
    spms = data['spms']  # (n_steps, n_agents, 16, 16, 3)
    n_steps, n_agents = spms.shape[0:2]

    # Average over time and agents for each channel
    avg_spm = np.mean(spms, axis=(0, 1))  # (16, 16, 3)

    # Compute spatial regions for averaged SPM
    regions = compute_spatial_regions(avg_spm)

    # Also compute variance across time/agents at each pixel
    pixel_temporal_var = np.var(spms, axis=(0, 1))  # (16, 16, 3)

    return avg_spm, regions, pixel_temporal_var

def visualize_spm_comparison(datasets, labels, output_path):
    """
    Create comprehensive SPM visualization comparing multiple Haze values

    Args:
        datasets: list of data dicts
        labels: list of labels (e.g., ["H=0.0", "H=0.5", "H=1.0"])
        output_path: save path for figure
    """
    n_datasets = len(datasets)

    fig = plt.figure(figsize=(20, 4 * n_datasets + 3))
    gs = gridspec.GridSpec(n_datasets + 1, 3, figure=fig, hspace=0.3, wspace=0.3)

    channel_names = ['Ch1: Occupancy', 'Ch2: Proximity Saliency', 'Ch3: Collision Risk']

    all_avg_spms = []
    all_regions = []

    # Plot each dataset
    for i, (data, label) in enumerate(zip(datasets, labels)):
        avg_spm, regions, _ = analyze_time_averaged_spm(data)
        all_avg_spms.append(avg_spm)
        all_regions.append(regions)

        haze_val = data['haze']
        beta_mean = np.mean(data['betas'][:, :, 0])  # beta_r
        precision_mean = np.mean(data['precisions'])

        # Plot each channel
        for ch_idx in range(3):
            ax = fig.add_subplot(gs[i, ch_idx])

            im = ax.imshow(avg_spm[:, :, ch_idx], cmap='hot', aspect='auto', origin='lower')
            ax.set_title(f'{label}: {channel_names[ch_idx]}\nβ={beta_mean:.1f}, Π={precision_mean:.2f}',
                        fontsize=10)
            ax.set_xlabel('Angular (θ)')
            ax.set_ylabel('Radial (ρ)')
            plt.colorbar(im, ax=ax)

            # Add variance annotation
            var_val = np.var(avg_spm[:, :, ch_idx])
            ax.text(0.02, 0.98, f'Var: {var_val:.5f}', transform=ax.transAxes,
                   verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.7),
                   fontsize=8)

    # Bottom row: Difference maps (if multiple datasets)
    if n_datasets >= 2:
        for ch_idx in range(3):
            ax = fig.add_subplot(gs[n_datasets, ch_idx])

            # Show difference: last - first
            diff = all_avg_spms[-1][:, :, ch_idx] - all_avg_spms[0][:, :, ch_idx]

            vmax = np.max(np.abs(diff))
            im = ax.imshow(diff, cmap='RdBu_r', aspect='auto', origin='lower',
                          vmin=-vmax, vmax=vmax)
            ax.set_title(f'Difference: {labels[-1]} - {labels[0]}\n{channel_names[ch_idx]}',
                        fontsize=10)
            ax.set_xlabel('Angular (θ)')
            ax.set_ylabel('Radial (ρ)')
            plt.colorbar(im, ax=ax)

            # Stats
            mean_diff = np.mean(np.abs(diff))
            ax.text(0.02, 0.98, f'|Δ|: {mean_diff:.5f}', transform=ax.transAxes,
                   verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.7),
                   fontsize=8)

    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"✅ SPM visualization saved to: {output_path}")
    plt.close()

    return all_avg_spms, all_regions

def generate_region_analysis_report(datasets, labels, all_regions):
    """Generate detailed text report of regional analysis"""
    print()
    print("=" * 80)
    print("SPM SPATIAL DISTRIBUTION ANALYSIS")
    print("=" * 80)
    print()

    # For each channel
    for ch_name in ['Occupancy', 'Proximity', 'Collision']:
        print(f"📊 {ch_name} Channel Analysis")
        print("-" * 80)

        # Global statistics
        print(f"  {'Label':<15} {'Mean':<10} {'Var':<12} {'Inner':<10} {'Outer':<10} {'Front':<10} {'Side':<10}")
        print("-" * 80)
        for label, regions in zip(labels, all_regions):
            r = regions[ch_name]
            print(f"  {label:<15} {r['global_mean']:<10.5f} {r['global_var']:<12.7f} "
                  f"{r['inner_mean']:<10.5f} {r['outer_mean']:<10.5f} "
                  f"{r['front_mean']:<10.5f} {r['side_mean']:<10.5f}")
        print()

        # Gradients
        print(f"  {'Label':<15} {'Radial Grad':<15} {'Angular Grad':<15}")
        print("-" * 80)
        for label, regions in zip(labels, all_regions):
            r = regions[ch_name]
            print(f"  {label:<15} {r['radial_gradient']:<15.5f} {r['angular_gradient']:<15.5f}")
        print()

        # Effect magnitude (if multiple datasets)
        if len(labels) >= 2:
            print(f"  Haze Effect ({labels[0]} → {labels[-1]}):")
            r0 = all_regions[0][ch_name]
            r1 = all_regions[-1][ch_name]

            delta_var = r1['global_var'] - r0['global_var']
            delta_inner = r1['inner_mean'] - r0['inner_mean']
            delta_outer = r1['outer_mean'] - r0['outer_mean']
            delta_radial_grad = r1['radial_gradient'] - r0['radial_gradient']

            print(f"    Δ Variance:         {delta_var:+.7f} ({100*delta_var/r0['global_var']:+.2f}%)")
            print(f"    Δ Inner Mean:       {delta_inner:+.5f}")
            print(f"    Δ Outer Mean:       {delta_outer:+.5f}")
            print(f"    Δ Radial Gradient:  {delta_radial_grad:+.5f}")
            print()

    print("=" * 80)

def analyze_fe_correlation(datasets, labels):
    """Analyze correlation between SPM characteristics and Free Energy"""
    print()
    print("=" * 80)
    print("FREE ENERGY vs SPM CORRELATION ANALYSIS")
    print("=" * 80)
    print()

    for i, (data, label) in enumerate(zip(datasets, labels)):
        print(f"📊 {label}")
        print("-" * 80)

        # Extract data
        spms = data['spms']  # (n_steps, n_agents, 16, 16, 3)
        fe = data['free_energies']  # (n_steps, n_agents, 4) = [F_goal, F_safety, S_u, F_total]

        # Ensure matching dimensions
        n_steps_spm = spms.shape[0]
        n_steps_fe = fe.shape[0]
        n_agents_spm = spms.shape[1]
        n_agents_fe = fe.shape[1]

        print(f"  SPM shape: {spms.shape}, FE shape: {fe.shape}")

        # Use minimum steps to align
        n_steps = min(n_steps_spm, n_steps_fe)
        n_agents = min(n_agents_spm, n_agents_fe)

        # Flatten for correlation with aligned dimensions
        ch2_mean = np.mean(spms[:n_steps, :n_agents, :, :, 1], axis=(2, 3)).flatten()
        ch2_var = np.var(spms[:n_steps, :n_agents, :, :, 1], axis=(2, 3)).flatten()
        ch3_mean = np.mean(spms[:n_steps, :n_agents, :, :, 2], axis=(2, 3)).flatten()
        ch3_var = np.var(spms[:n_steps, :n_agents, :, :, 2], axis=(2, 3)).flatten()

        F_goal = fe[:n_steps, :n_agents, 0].flatten()
        F_safety = fe[:n_steps, :n_agents, 1].flatten()
        S_u = fe[:n_steps, :n_agents, 2].flatten()
        F_total = fe[:n_steps, :n_agents, 3].flatten()

        print(f"  Aligned samples: {len(ch2_mean)}")

        # Compute correlations
        print(f"  Correlation with F_safety:")
        print(f"    Ch2 Mean:      {np.corrcoef(ch2_mean, F_safety)[0,1]:.4f}")
        print(f"    Ch2 Variance:  {np.corrcoef(ch2_var, F_safety)[0,1]:.4f}")
        print(f"    Ch3 Mean:      {np.corrcoef(ch3_mean, F_safety)[0,1]:.4f}")
        print(f"    Ch3 Variance:  {np.corrcoef(ch3_var, F_safety)[0,1]:.4f}")
        print()

        print(f"  Correlation with S(u):")
        print(f"    Ch2 Mean:      {np.corrcoef(ch2_mean, S_u)[0,1]:.4f}")
        print(f"    Ch2 Variance:  {np.corrcoef(ch2_var, S_u)[0,1]:.4f}")
        print(f"    Ch3 Mean:      {np.corrcoef(ch3_mean, S_u)[0,1]:.4f}")
        print(f"    Ch3 Variance:  {np.corrcoef(ch3_var, S_u)[0,1]:.4f}")
        print()

    print("=" * 80)

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  Single file analysis:")
        print("    python analyze_spm_spatial_distribution.py <file.h5>")
        print()
        print("  Multi-file comparison:")
        print("    python analyze_spm_spatial_distribution.py <file1.h5> <file2.h5> ...")
        sys.exit(1)

    filepaths = sys.argv[1:]

    print("=" * 80)
    print("Loading simulation data...")
    print("=" * 80)

    datasets = []
    labels = []

    for filepath in filepaths:
        print(f"  Loading: {filepath}")
        data = load_simulation_data(filepath)
        datasets.append(data)
        labels.append(f"H={data['haze']:.1f}")

    print()

    # Create visualization
    output_dir = Path("results/spm_analysis")
    output_dir.mkdir(parents=True, exist_ok=True)

    output_path = output_dir / "spm_spatial_comparison.png"
    all_avg_spms, all_regions = visualize_spm_comparison(datasets, labels, output_path)

    # Generate region analysis
    generate_region_analysis_report(datasets, labels, all_regions)

    # Analyze FE correlation
    analyze_fe_correlation(datasets, labels)

    print()
    print("=" * 80)
    print("✅ SPM spatial analysis complete!")
    print("=" * 80)

if __name__ == "__main__":
    main()
