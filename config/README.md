# Config Directory

**Status**: Currently unused (placeholder)

This directory was originally planned for Phase 4.5 configuration files but is not currently used in EPH v5.6.

---

## Current Configuration Location

All configuration is managed through Julia modules:

- **src/config.jl**: Base configuration (SPMParams, WorldParams, AgentParams)
- **src/config_v56.jl**: EPH v5.6 specific configuration (ControlParamsV56)

---

## Future Use

This directory may be used in future versions for:
- External YAML/JSON configuration files
- Experiment presets
- Hyperparameter search spaces

**Current Status**: Not in use, safe to ignore
