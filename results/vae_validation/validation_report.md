# VAE Validation Report (v5.6)

**Date**: 2026-01-10 23:56:26
**Model**: models/action_vae_v56_best.bson

## 1. Prediction Accuracy

### Test IID (In-Distribution)
- Overall MSE: 0.045612
- Channel 1 MSE: 0.076575
- Channel 2 MSE: 0.0415
- Channel 3 MSE: 0.01876

### Test OOD (Out-of-Distribution)
- Overall MSE: 0.045427
- Channel 1 MSE: 0.076188
- Channel 2 MSE: 0.041332
- Channel 3 MSE: 0.01876

## 2. Counterfactual Surprise
- Success Rate: 52.0%
- Mean S(safe): 63.6549
- Mean S(risky): 63.445

## 3. Surprise-Error Correlation
- Spearman ρ: 0.9262

## Success Criteria
- Test IID MSE < 0.05: ✅
- Counterfactual > 70%: ❌
- Correlation > 0.4: ✅
- Test OOD MSE < 0.1: ✅

**Overall**: 3 / 4 passed
