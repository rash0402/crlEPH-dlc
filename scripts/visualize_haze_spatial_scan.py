#!/usr/bin/env python3
"""
Visualize Haze Spatial Scan Results

複数のパフォーマンス指標をヒートマップで可視化：
1. Coverage (%) - 環境探索率
2. Collision count - 衝突回数
3. Path efficiency - パス効率
4. Novelty rate (%) - 新規訪問率

Usage:
    python scripts/visualize_haze_spatial_scan.py <results_json_file>
"""

import json
import sys
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

def load_results(json_file):
    """Load experimental results from JSON file."""
    with open(json_file, 'r') as f:
        data = json.load(f)
    return data

def create_heatmap_data(results, metric_key, Nr, Nθ):
    """
    Create 2D array for heatmap visualization.

    Args:
        results: List of aggregated results
        metric_key: Key to extract (e.g., "coverage_mean")
        Nr: Number of radial bins
        Nθ: Number of angular bins

    Returns:
        2D numpy array (Nr-1, Nθ-1)
    """
    heatmap = np.full((Nr-1, Nθ-1), np.nan)

    for result in results:
        r_pos = result["r_pos"]
        θ_pos = result["θ_pos"]
        value = result[metric_key]

        # Convert to 0-indexed
        r_idx = r_pos - 1
        θ_idx = θ_pos - 1

        if 0 <= r_idx < (Nr-1) and 0 <= θ_idx < (Nθ-1):
            heatmap[r_idx, θ_idx] = value

    return heatmap

def plot_heatmaps(data, output_dir):
    """
    Create multi-panel heatmap figure.

    Args:
        data: Loaded JSON data
        output_dir: Directory to save output figure
    """
    metadata = data["metadata"]
    aggregated = data["aggregated_results"]
    baseline = data["baseline"]

    Nr = metadata["Nr"]
    Nθ = metadata["Nθ"]
    fov = metadata["fov_angle_degrees"]
    multiplier = metadata["haze_multiplier"]

    # Create heatmaps for each metric
    metrics = [
        ("coverage_mean", "Coverage (%)", 100, "viridis", False),
        ("collision_mean", "Collision Count", 1, "Reds", False),
        ("compactness_mean", "Compactness (Shepherding)", 1, "plasma", False),  # NEW!
        ("path_efficiency_mean", "Path Efficiency", 1, "viridis_r", False),
        ("novelty_rate_mean", "Novelty Rate (%)", 100, "Blues", False),
    ]

    fig, axes = plt.subplots(2, 3, figsize=(18, 12))
    fig.suptitle(f"Haze Spatial Scan: 3×3 Patch Position Effect (FOV={fov}°, Multiplier={multiplier}x)",
                 fontsize=16, fontweight='bold')

    axes = axes.flatten()

    for idx, (metric_key, title, scale, cmap, reverse) in enumerate(metrics):
        ax = axes[idx]

        # Create heatmap data
        heatmap = create_heatmap_data(aggregated, metric_key, Nr, Nθ)

        # Scale values
        heatmap_scaled = heatmap * scale

        # Angular labels (degrees)
        θ_labels = []
        for θ_idx in range(Nθ-1):
            θ_deg = -180 + (θ_idx + 0.5) * (360 / Nθ)
            θ_labels.append(f"{int(θ_deg)}°")

        # Radial labels
        radial_labels = [f"R{i+1}-{i+2}" for i in range(Nr-1)]

        # Plot heatmap
        im = ax.imshow(heatmap_scaled, cmap=cmap, aspect='auto', origin='lower',
                      interpolation='nearest')

        # Add baseline line (if applicable)
        if metric_key in baseline:
            baseline_val = baseline[metric_key] * scale
            # We don't have a direct way to show baseline in heatmap, but we can note it in title
            ax.set_title(f"{title}\n(Baseline: {baseline_val:.1f})", fontsize=12, fontweight='bold')
        else:
            ax.set_title(title, fontsize=12, fontweight='bold')

        # Add colorbar
        cbar = plt.colorbar(im, ax=ax, orientation='vertical', pad=0.02)

        # Set ticks
        ax.set_xticks(np.arange(Nθ-1))
        ax.set_yticks(np.arange(Nr-1))
        ax.set_xticklabels(θ_labels, rotation=45, ha='right')
        ax.set_yticklabels(radial_labels)

        # Labels
        ax.set_xlabel("Angular Position (θ)", fontsize=10, fontweight='bold')
        ax.set_ylabel("Radial Position (r)", fontsize=10, fontweight='bold')

        # Add grid
        ax.set_xticks(np.arange(Nθ-1) - 0.5, minor=True)
        ax.set_yticks(np.arange(Nr-1) - 0.5, minor=True)
        ax.grid(which='minor', color='gray', linestyle='-', linewidth=0.5, alpha=0.3)

        # Annotate values
        for r_idx in range(Nr-1):
            for θ_idx in range(Nθ-1):
                value = heatmap_scaled[r_idx, θ_idx]
                if not np.isnan(value):
                    text_color = 'white' if value < np.nanmean(heatmap_scaled) else 'black'
                    ax.text(θ_idx, r_idx, f"{value:.1f}",
                           ha='center', va='center', color=text_color, fontsize=8)

    # Hide the last subplot (we have 5 metrics in 2×3 grid)
    axes[-1].axis('off')

    plt.tight_layout()

    # Save figure
    output_path = output_dir / "haze_spatial_scan_heatmaps.png"
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"Heatmap saved to: {output_path}")

    # Also save as PDF for publication
    output_pdf = output_dir / "haze_spatial_scan_heatmaps.pdf"
    plt.savefig(output_pdf, bbox_inches='tight')
    print(f"PDF saved to: {output_pdf}")

    plt.show()

def plot_difference_from_baseline(data, output_dir):
    """
    Plot difference from baseline for coverage metric.

    Args:
        data: Loaded JSON data
        output_dir: Directory to save output figure
    """
    metadata = data["metadata"]
    aggregated = data["aggregated_results"]
    baseline = data["baseline"]

    Nr = metadata["Nr"]
    Nθ = metadata["Nθ"]

    # Create difference heatmap for coverage
    heatmap = create_heatmap_data(aggregated, "coverage_mean", Nr, Nθ)
    baseline_coverage = baseline["coverage"]

    # Compute difference
    diff_heatmap = (heatmap - baseline_coverage) * 100  # in percentage points

    fig, ax = plt.subplots(1, 1, figsize=(10, 8))
    fig.suptitle("Coverage Δ vs Baseline (percentage points)", fontsize=14, fontweight='bold')

    # Angular labels
    θ_labels = []
    for θ_idx in range(Nθ-1):
        θ_deg = -180 + (θ_idx + 0.5) * (360 / Nθ)
        θ_labels.append(f"{int(θ_deg)}°")

    # Radial labels
    radial_labels = [f"R{i+1}-{i+2}" for i in range(Nr-1)]

    # Plot with diverging colormap
    vmax = max(abs(np.nanmin(diff_heatmap)), abs(np.nanmax(diff_heatmap)))
    im = ax.imshow(diff_heatmap, cmap='RdYlGn', aspect='auto', origin='lower',
                  interpolation='nearest', vmin=-vmax, vmax=vmax)

    # Colorbar
    cbar = plt.colorbar(im, ax=ax, orientation='vertical', pad=0.02)
    cbar.set_label("Δ Coverage (%)", fontsize=10)

    # Set ticks
    ax.set_xticks(np.arange(Nθ-1))
    ax.set_yticks(np.arange(Nr-1))
    ax.set_xticklabels(θ_labels, rotation=45, ha='right')
    ax.set_yticklabels(radial_labels)

    # Labels
    ax.set_xlabel("Angular Position (θ)", fontsize=11, fontweight='bold')
    ax.set_ylabel("Radial Position (r)", fontsize=11, fontweight='bold')

    # Grid
    ax.set_xticks(np.arange(Nθ-1) - 0.5, minor=True)
    ax.set_yticks(np.arange(Nr-1) - 0.5, minor=True)
    ax.grid(which='minor', color='gray', linestyle='-', linewidth=0.5, alpha=0.3)

    # Annotate
    for r_idx in range(Nr-1):
        for θ_idx in range(Nθ-1):
            value = diff_heatmap[r_idx, θ_idx]
            if not np.isnan(value):
                text_color = 'black' if abs(value) < vmax/2 else 'white'
                ax.text(θ_idx, r_idx, f"{value:+.1f}",
                       ha='center', va='center', color=text_color, fontsize=9, fontweight='bold')

    plt.tight_layout()

    # Save
    output_path = output_dir / "haze_spatial_scan_difference.png"
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    print(f"Difference heatmap saved to: {output_path}")

    plt.show()

def print_statistics(data):
    """Print summary statistics."""
    aggregated = data["aggregated_results"]
    baseline = data["baseline"]

    print("\n" + "="*60)
    print("  Statistical Summary")
    print("="*60)

    # Coverage
    coverages = [r["coverage_mean"] for r in aggregated]
    print("\nCoverage:")
    print(f"  Baseline:      {baseline['coverage']*100:.1f}%")
    print(f"  Mean (scan):   {np.mean(coverages)*100:.1f}%")
    print(f"  Min:           {np.min(coverages)*100:.1f}%")
    print(f"  Max:           {np.max(coverages)*100:.1f}%")
    print(f"  Range:         {(np.max(coverages) - np.min(coverages))*100:.1f}%")

    # Find best position
    best_idx = np.argmax(coverages)
    best_result = aggregated[best_idx]
    print(f"\n  Best position:")
    print(f"    (r={best_result['r_pos']}, θ={best_result['θ_pos']} ≈ {best_result['θ_deg']:.0f}°)")
    print(f"    Coverage: {best_result['coverage_mean']*100:.1f}%")
    print(f"    Δ vs Baseline: {(best_result['coverage_mean'] - baseline['coverage'])*100:+.1f}%")

    # Collisions
    collisions = [r["collision_mean"] for r in aggregated]
    print("\nCollisions:")
    print(f"  Baseline:      {baseline['collision_count']:.1f}")
    print(f"  Mean (scan):   {np.mean(collisions):.1f}")
    print(f"  Min:           {np.min(collisions):.0f}")
    print(f"  Max:           {np.max(collisions):.0f}")

    # Compactness (NEW: Shepherding metric)
    compactness = [r["compactness_mean"] for r in aggregated]
    print("\nCompactness (Shepherding metric):")
    print(f"  Baseline:      {baseline.get('compactness_mean', 0):.6f}")
    print(f"  Mean (scan):   {np.mean(compactness):.6f}")
    print(f"  Min:           {np.min(compactness):.6f}")
    print(f"  Max:           {np.max(compactness):.6f}")
    print(f"  Range:         {(np.max(compactness) - np.min(compactness)):.6f}")

    # Find best compactness position
    best_compact_idx = np.argmax(compactness)
    best_compact = aggregated[best_compact_idx]
    print(f"\n  Best Compactness (highest = most compact):")
    print(f"    (r={best_compact['r_pos']}, θ={best_compact['θ_pos']} ≈ {best_compact['θ_deg']:.0f}°)")
    print(f"    Compactness: {best_compact['compactness_mean']:.6f}")
    print(f"    Δ vs Baseline: {(best_compact['compactness_mean'] - baseline.get('compactness_mean', 0)):.6f}")

    print("\n" + "="*60)

def main():
    if len(sys.argv) < 2:
        print("Usage: python visualize_haze_spatial_scan.py <results_json_file>")
        sys.exit(1)

    json_file = sys.argv[1]

    # Load data
    print(f"Loading results from: {json_file}")
    data = load_results(json_file)

    # Output directory
    output_dir = Path(json_file).parent

    # Print statistics
    print_statistics(data)

    # Create visualizations
    print("\nGenerating heatmaps...")
    plot_heatmaps(data, output_dir)

    print("\nGenerating difference heatmap...")
    plot_difference_from_baseline(data, output_dir)

    print("\n✓ Visualization complete!")

if __name__ == "__main__":
    main()
