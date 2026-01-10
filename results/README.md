# EPH v5.6 Results Directory

This directory contains analysis results (reports, figures, statistics) for EPH v5.6.

## Directory Structure

```
results/
├── data_collection/       # Phase 1: Dataset statistics
│   ├── dataset_summary.md
│   └── distribution_plots.png
├── vae_training/          # Phase 2: VAE learning curves
│   ├── training_log.csv
│   ├── loss_curves.png
│   └── hyperparameter_comparison.md
├── vae_validation/        # Phase 3: VAE validation reports
│   ├── prediction_report.md
│   ├── counterfactual_surprise.png
│   └── surprise_error_correlation.png
├── control_integration/   # Phase 4: Control integration visualization
│   ├── scramble_freezing_analysis.png
│   └── corridor_throughput_analysis.png
├── comparison/            # Phase 5.1-5.4: Ablation & comparison
│   ├── comparison_report.md
│   ├── freezing_vs_density.png
│   └── statistical_tests.csv
├── haze_sensitivity/      # Phase 5.5: Haze parametric study
│   ├── raw_results.csv
│   ├── sensitivity_report.md
│   ├── scramble_haze_vs_freezing.png
│   ├── scramble_heatmap.png
│   ├── corridor_haze_vs_throughput.png
│   └── corridor_heatmap.png
└── self_hazing/           # Phase 6: Self-Hazing meta-learning
    ├── meta_learning_log.csv
    └── optimal_haze_policy_report.md
```

## File Types

- **Markdown (*.md)**: Analysis reports, summaries
- **PNG (*.png)**: Figures, plots, visualizations
- **CSV (*.csv)**: Raw statistics, experimental results

## Usage

These files are Git-managed (unlike `data/logs/` which is excluded).
Results should be referenced directly in papers and presentations.

## Version History

- **v5.6** (2026-01-10): Current version with Surprise integration
- **v5.5** (archived in `archive/v55_results/`): Previous experiments

## Notes

✅ Git-managed (small file sizes)
📊 Raw data is in `data/logs/` (Git-excluded)
📝 Reports should be self-contained with embedded figures
