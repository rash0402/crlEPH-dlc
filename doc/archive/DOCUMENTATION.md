# EPH v5.6 Documentation Index

Quick reference guide to all project documentation.

## 📚 Core Documentation (doc/)

| Document | Size | Purpose | When to Use |
|----------|------|---------|-------------|
| **[proposal_v5.6.md](doc/proposal_v5.6.md)** | 52 KB | Complete research proposal | Paper writing, grant applications |
| **[framework_v5.6.md](doc/framework_v5.6.md)** | 14 KB | Theoretical framework | Quick reference, algorithm design |
| **[implementation_plan_v5.6.md](doc/implementation_plan_v5.6.md)** | 51 KB | Phase-by-phase implementation | Development workflow, task tracking |

**Total**: 3 files, ~117 KB

---

## 🚀 Quick Start Guides

### New Developers
1. Read: `CLAUDE.md` (Development guidelines)
2. Read: `SETUP.md` (Environment setup)
3. Read: `doc/framework_v5.6.md` (Theoretical overview)
4. Follow: `doc/implementation_plan_v5.6.md` (Phase 0)

### Paper Writing
1. Reference: `doc/proposal_v5.6.md` (Sections 1-5)
2. Results: `results/*/` (Analysis figures and reports)
3. Methods: `doc/framework_v5.6.md` (Mathematical formulation)

### Code Implementation
1. Plan: `doc/implementation_plan_v5.6.md`
2. Style: `CLAUDE.md`
3. Structure: `data/logs/README.md`, `results/README.md`

---

## 📁 Project Structure Documentation

| File | Description |
|------|-------------|
| `README.md` | Project overview (main) |
| `CLAUDE.md` | Claude Code integration guide |
| `SETUP.md` | Installation and setup instructions |
| `DOCUMENTATION.md` | This file - documentation index |
| `CLEANUP_SUMMARY.md` | v5.6 cleanup and restructuring log |
| `data/logs/README.md` | Log directory structure |
| `results/README.md` | Results directory structure |
| `doc/README.md` | Core documentation guide |
| `archive/README.md` | Archived v5.5 data and docs |

---

## 🎯 Development Workflow

### Phase 0: Setup
```bash
# Read documentation
cat doc/implementation_plan_v5.6.md  # Phase 0 section

# Setup environment
./scripts/setup.sh  # Or follow SETUP.md
```

### Phase 1: Data Collection
```bash
# Implement data collection
# Output: data/vae_training/raw/{scramble,corridor}/
# Results: results/data_collection/
```

### Phase 2-6: Implementation
Follow `doc/implementation_plan_v5.6.md` for detailed steps.

---

## 📊 Key Concepts (Quick Reference)

### Free Energy (v5.6)
```
F(u) = F_goal(u) + F_safety(u) + λ_s·S(u)
```

### Haze Modes
1. **Fixed**: Haze = 0.5 (Phase 1-5)
2. **Scheduled**: Haze = f(density, risk)
3. **Self-Adaptive**: Haze = π_haze(obs) (Phase 6)

### Scenarios
- **Scramble Crossing**: 4-group intersection
- **Corridor**: Bidirectional narrow passage

---

## 🗄️ Archived Documentation

**Location**: `archive/`

- `v55_docs/` - v5.5 documentation (proposals, reports)
- `v55_logs/` - v5.5 simulation logs (~304 MB)
- `v55_results/` - v5.5 analysis results (~1.2 MB)

**Note**: Archives are for reference only. Use v5.6 documents for current work.

---

## 📝 Document Types

### Markdown Files (*.md)
- Research proposals
- Technical documentation
- READMEs and guides
- Analysis reports

### Code Documentation
- Inline comments: Julia docstrings
- Module headers: Purpose and exports
- Function docs: Parameters and returns

### Data Documentation
- HDF5 metadata: Simulation parameters
- CSV headers: Column descriptions
- PNG captions: In report files

---

## 🔗 External Resources

- **Free Energy Principle**: Friston et al. (2006-2023)
- **Active Inference**: Parr et al. (2022)
- **Julia Documentation**: https://docs.julialang.org/
- **Flux.jl (VAE)**: https://fluxml.ai/

---

## 📅 Version History

| Version | Date | Status | Docs Location |
|---------|------|--------|---------------|
| **v5.6** | 2026-01-10 | ✅ Current | `doc/` |
| v5.5 | 2025-12 | Archived | `archive/v55_docs/` |

---

## 💡 Tips

1. **Finding information**:
   - Theory → `doc/framework_v5.6.md`
   - Implementation → `doc/implementation_plan_v5.6.md`
   - Background → `doc/proposal_v5.6.md`

2. **Understanding structure**:
   - Data flow → `doc/implementation_plan_v5.6.md` (Phase 0)
   - Output locations → `data/logs/README.md`, `results/README.md`

3. **Development**:
   - Always check success criteria in implementation plan
   - Follow Phase order (0→1→2→3→4→5→6)
   - Use Git for results/, not for data/logs/

---

**Last Updated**: 2026-01-10
**Maintained by**: EPH v5.6 Development Team

For questions about documentation structure, see `doc/README.md`.
