#!/usr/bin/env python3
"""
Analyze Experiment 1: Lubricant Effect Results

Compares Low Haze vs High Haze conditions on narrow passage navigation.
Metrics: Success rate, average velocity, wall clearance
"""

import json
import sys
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
from scipy import stats

def load_results(filepath):
    """Load experiment results from JSON file"""
    with open(filepath, 'r') as f:
        return json.load(f)

def extract_metrics(results):
    """Extract metrics by condition"""
    low_haze = [r for r in results if r['haze_level'] == 'low']
    high_haze = [r for r in results if r['haze_level'] == 'high']

    metrics = {
        'low': {
            'success_rate': np.mean([r['success'] for r in low_haze]),
            'avg_velocity': [r['avg_velocity'] for r in low_haze],
            'min_clearance': [r['min_clearance'] for r in low_haze],
            'pass_through_time': [r['pass_through_time'] for r in low_haze if r['success']]
        },
        'high': {
            'success_rate': np.mean([r['success'] for r in high_haze]),
            'avg_velocity': [r['avg_velocity'] for r in high_haze],
            'min_clearance': [r['min_clearance'] for r in high_haze],
            'pass_through_time': [r['pass_through_time'] for r in high_haze if r['success']]
        }
    }

    return metrics

def statistical_analysis(metrics):
    """Perform statistical tests"""
    print("\n" + "="*60)
    print("STATISTICAL ANALYSIS - Experiment 1: Lubricant Effect")
    print("="*60)

    # Success Rate
    print("\n[Success Rate]")
    print(f"  Low Haze:  {metrics['low']['success_rate']*100:.1f}%")
    print(f"  High Haze: {metrics['high']['success_rate']*100:.1f}%")

    # Average Velocity (t-test)
    print("\n[Average Velocity]")
    low_vel = np.array(metrics['low']['avg_velocity'])
    high_vel = np.array(metrics['high']['avg_velocity'])

    print(f"  Low Haze:  μ={np.mean(low_vel):.3f}, σ={np.std(low_vel):.3f}")
    print(f"  High Haze: μ={np.mean(high_vel):.3f}, σ={np.std(high_vel):.3f}")

    if len(low_vel) > 1 and len(high_vel) > 1:
        t_stat, p_value = stats.ttest_ind(low_vel, high_vel)
        print(f"  t-test: t={t_stat:.3f}, p={p_value:.4f}")
        if p_value < 0.05:
            print(f"  ✓ Significant difference (p < 0.05)")
        else:
            print(f"  ✗ No significant difference (p >= 0.05)")

    # Wall Clearance (t-test) - KEY METRIC for lubricant effect
    print("\n[Wall Clearance] ← KEY METRIC")
    low_clear = np.array(metrics['low']['min_clearance'])
    high_clear = np.array(metrics['high']['min_clearance'])

    print(f"  Low Haze:  μ={np.mean(low_clear):.3f}, σ={np.std(low_clear):.3f}")
    print(f"  High Haze: μ={np.mean(high_clear):.3f}, σ={np.std(high_clear):.3f}")
    print(f"  Difference: {np.mean(high_clear) - np.mean(low_clear):.3f} " +
          f"({(np.mean(high_clear) / np.mean(low_clear) - 1)*100:.1f}% increase)")

    if len(low_clear) > 1 and len(high_clear) > 1:
        t_stat, p_value = stats.ttest_ind(low_clear, high_clear)
        print(f"  t-test: t={t_stat:.3f}, p={p_value:.4f}")
        if p_value < 0.05:
            print(f"  ✓ Significant difference (p < 0.05)")
            print(f"  → Lubricant Effect CONFIRMED")
        else:
            print(f"  ✗ No significant difference (p >= 0.05)")
            print(f"  → Lubricant Effect NOT CONFIRMED")

    # Pass-through Time
    print("\n[Pass-through Time]")
    if len(metrics['low']['pass_through_time']) > 0 and len(metrics['high']['pass_through_time']) > 0:
        low_time = np.array(metrics['low']['pass_through_time'])
        high_time = np.array(metrics['high']['pass_through_time'])

        print(f"  Low Haze:  μ={np.mean(low_time):.1f} steps, σ={np.std(low_time):.1f}")
        print(f"  High Haze: μ={np.mean(high_time):.1f} steps, σ={np.std(high_time):.1f}")

        if len(low_time) > 1 and len(high_time) > 1:
            t_stat, p_value = stats.ttest_ind(low_time, high_time)
            print(f"  t-test: t={t_stat:.3f}, p={p_value:.4f}")

def visualize_results(metrics, output_path):
    """Create visualization of results"""
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))

    # Plot 1: Success Rate
    ax = axes[0]
    success_rates = [metrics['low']['success_rate'] * 100,
                     metrics['high']['success_rate'] * 100]
    bars = ax.bar(['Low Haze', 'High Haze'], success_rates,
                   color=['#ff6b6b', '#4ecdc4'], alpha=0.7)
    ax.set_ylabel('Success Rate (%)', fontsize=12)
    ax.set_title('Navigation Success Rate', fontsize=14, fontweight='bold')
    ax.set_ylim([0, 105])
    ax.axhline(y=100, color='gray', linestyle='--', alpha=0.3)

    for bar, rate in zip(bars, success_rates):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{rate:.1f}%', ha='center', va='bottom', fontsize=11)

    # Plot 2: Wall Clearance (Box Plot)
    ax = axes[1]
    data_clearance = [metrics['low']['min_clearance'],
                      metrics['high']['min_clearance']]
    bp = ax.boxplot(data_clearance, labels=['Low Haze', 'High Haze'],
                     patch_artist=True, notch=True)

    for patch, color in zip(bp['boxes'], ['#ff6b6b', '#4ecdc4']):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)

    ax.set_ylabel('Minimum Wall Clearance (px)', fontsize=12)
    ax.set_title('Wall Clearance Distribution\n(Higher = More confident navigation)',
                 fontsize=14, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)

    # Add mean markers
    for i, data in enumerate(data_clearance, 1):
        mean_val = np.mean(data)
        ax.plot(i, mean_val, 'r*', markersize=15, label='Mean' if i == 1 else '')

    ax.legend()

    # Plot 3: Pass-through Time
    ax = axes[2]
    if len(metrics['low']['pass_through_time']) > 0 and len(metrics['high']['pass_through_time']) > 0:
        data_time = [metrics['low']['pass_through_time'],
                     metrics['high']['pass_through_time']]
        bp = ax.boxplot(data_time, labels=['Low Haze', 'High Haze'],
                        patch_artist=True, notch=True)

        for patch, color in zip(bp['boxes'], ['#ff6b6b', '#4ecdc4']):
            patch.set_facecolor(color)
            patch.set_alpha(0.7)

        ax.set_ylabel('Pass-through Time (steps)', fontsize=12)
        ax.set_title('Time to Navigate Corridor\n(Lower = Faster)',
                     fontsize=14, fontweight='bold')
        ax.grid(axis='y', alpha=0.3)

        # Add mean markers
        for i, data in enumerate(data_time, 1):
            mean_val = np.mean(data)
            ax.plot(i, mean_val, 'r*', markersize=15, label='Mean' if i == 1 else '')

        ax.legend()

    plt.suptitle('Experiment 1: Lubricant Effect Analysis\nHaze reduces excessive collision avoidance',
                 fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()

    # Save figure
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"\n✓ Visualization saved to: {output_path}")

    # Show plot
    plt.show()

def main():
    if len(sys.argv) < 2:
        # Find most recent results file
        exp_dir = Path(__file__).parent.parent / 'data' / 'experiments'
        json_files = list(exp_dir.glob('exp1_lubricant_effect_*.json'))

        if not json_files:
            print("Error: No experiment results found")
            print("Usage: python analyze_exp1.py [results.json]")
            sys.exit(1)

        # Use most recent file
        filepath = max(json_files, key=lambda p: p.stat().st_mtime)
        print(f"Using most recent results: {filepath.name}")
    else:
        filepath = Path(sys.argv[1])

    # Load results
    results = load_results(filepath)
    print(f"\nLoaded {len(results)} trials")

    # Extract metrics
    metrics = extract_metrics(results)

    # Statistical analysis
    statistical_analysis(metrics)

    # Visualize
    output_path = filepath.parent / f"{filepath.stem}_analysis.png"
    visualize_results(metrics, output_path)

    print("\n" + "="*60)
    print("INTERPRETATION")
    print("="*60)
    print("""
The Lubricant Effect hypothesis predicts that HIGH HAZE should:
  1. Maintain similar success rates (agents still navigate successfully)
  2. INCREASE wall clearance (less over-cautious collision avoidance)
  3. Potentially reduce navigation time (smoother, less hesitant movement)

If High Haze shows significantly HIGHER wall clearance while maintaining
success rate, this CONFIRMS the lubricant effect: Haze reduces excessive
precision that causes over-cautious collision avoidance.
    """)

if __name__ == '__main__':
    main()
