# Current Task

**Last Updated:** 2025-11-24 (Auto-update this timestamp when modifying)

---

## Task Overview

**Task ID:** 2025-11-24-fix-gui-startup-error
**Status:** ✅ COMPLETED
**Priority:** High
**Assignee:** Claude Code
**Started:** 2025-11-24
**Completed:** 2025-11-24

---

## Objective

Fix "Package `serena` does not provide any executables" error in start_gui.sh script.

---

## Background / Context

User attempted to run `./scripts/start_gui.sh` and encountered error:
```
Package `serena` does not provide any executables.
```

**Root Cause:** The script incorrectly assumed `serena` was a PyPI package with executables (using `uvx serena start-dashboard` or `python3 -m serena start-dashboard`). However, the GUI is actually a PySide6 desktop application in the `gui/` directory, not a web-based Dash/Serena application.

---

## Scope

### In Scope
- ✅ Create GUI entry point (`gui/__main__.py`)
- ✅ Update `scripts/start_gui.sh` to use correct entry point
- ✅ Remove incorrect serena package references
- ✅ Add proper dependency checks (Python3, PySide6)
- ✅ Test GUI startup

### Out of Scope
- GUI feature improvements
- Fixing Qt font warnings (cosmetic only)

---

## Approach / Solution

### Steps
1. ✅ **Investigate GUI structure**
   - Found `gui/main_window.py` defines MainWindow class
   - Discovered no entry point (`__main__.py`) existed
   - Identified incorrect serena package references in startup script

2. ✅ **Create GUI entry point**
   - Created `gui/__main__.py` with proper PySide6 initialization
   - Implemented main() function with QApplication setup
   - Enabled `python3 -m gui` execution pattern

3. ✅ **Fix start_gui.sh script**
   - Removed port 8050 check (not needed for desktop GUI)
   - Removed uvx/serena package logic
   - Simplified to use `python3 -m gui` directly
   - Added PySide6 dependency check
   - Updated header comment to reflect PySide6 (not Serena)

4. ✅ **Test and verify**
   - Ran `./scripts/start_gui.sh` successfully
   - GUI window launched without errors
   - Confirmed all checks pass (Python3, PySide6)

---

## Progress

### Completed
- [x] Analyzed GUI directory structure
- [x] Created `gui/__main__.py` entry point (~30 lines)
- [x] Updated `scripts/start_gui.sh` (simplified from 81 to 56 lines)
- [x] Removed serena package references
- [x] Added proper dependency checks
- [x] Tested GUI startup successfully

### In Progress
- None (task completed)

### Blocked
- None

---

## Key Files Modified

| File | Status | Description |
|------|--------|-------------|
| `gui/__main__.py` | ✅ Created | GUI entry point for `python3 -m gui` execution |
| `scripts/start_gui.sh` | ✅ Modified | Fixed to use PySide6 GUI instead of serena package |

---

## Testing / Validation

### Manual Testing
```bash
./scripts/start_gui.sh
```

**Results:**
- ✅ Python3 detected successfully
- ✅ PySide6 detected successfully
- ✅ GUI window launched
- ⚠️ Qt font warning (cosmetic only): "Populating font family aliases took 107 ms"
- ✅ All tabs loaded correctly (Validation, GRU Training, Experiments, Analysis)

**Conclusion:** GUI startup fixed and working correctly.

---

## Open Questions / Decisions Needed

- None (task completed)

## Resolution Summary

**Problem:** Script tried to run non-existent `serena` package via `uvx serena start-dashboard`

**Solution:** Created proper PySide6 entry point and updated script to use `python3 -m gui`

**Result:** GUI now launches successfully via `./scripts/start_gui.sh`

---

## Next Steps

After completing this task, potential next tasks include:

1. **Phase 4 Experimental Validation**
   - Design experiments to test Full Tensor Haze capabilities
   - Compare channel-selective attention vs. uniform precision
   - Measure performance in obstacle-rich environments

2. **Phase 3 Shepherding Experiments**
   - Continue shepherding task experiments
   - Collect metrics (success rate, task time)
   - Analyze GRU predictor effectiveness

3. **GRU Model Training**
   - Collect training data via `scripts/collect_gru_training_data.sh`
   - Train predictor using `scripts/gru/update_gru.sh`
   - Evaluate prediction accuracy

4. **Documentation Enhancement**
   - Add Phase 4 experimental reports to `doc/experimental_reports/`
   - Create tutorial for new contributors
   - Add architecture diagrams

---

## Notes / Observations

### Documentation Structure (Current)
```
doc/
├── PHASE_GUIDE.md              # Phase theory and architecture (comprehensive)
├── VALIDATION_PHILOSOPHY.md    # Why validation matters (newly created)
├── EPH_Implementation_Guide_Julia.md
├── EPH_Active_Inference_Derivation.md
└── ...

scripts/
└── README.md                   # Script usage guide (newly recreated)

CLAUDE.md                       # AI assistant instructions (updated)
CURRENT_TASK.md                # This file (task tracking)
```

### Task Tracking Workflow (New)
```
1. Read CURRENT_TASK.md
   ↓
2. Work on task
   ↓
3. Update CURRENT_TASK.md
   ↓
4. Run validation (if code changed)
   ↓
5. Commit (including CURRENT_TASK.md)
```

### Serena Integration
- MCP Serena onboarded successfully
- Recommended approach: Use symbolic tools over full file reads
- Key modules identified: Types.jl, SPM.jl, EPH.jl, FullTensorHaze.jl, Simulation.jl

---

## References

- **Task tracking workflow:** See `CLAUDE.md` § Task Tracking and Workflow
- **Script usage:** See `scripts/README.md`
- **Phase details:** See `doc/PHASE_GUIDE.md`
- **Validation philosophy:** See `doc/VALIDATION_PHILOSOPHY.md`
- **Git commit:** 14a62b6 (GUI), 836120b (Phase guide), 95134cb (Phase 2)

---

## Template Instructions (for future tasks)

When starting a new task:
1. Copy this template structure
2. Update Task ID (format: YYYY-MM-DD-task-name)
3. Set Status to 🔄 IN_PROGRESS
4. Fill in Objective, Background, Scope
5. Document approach and progress as you work
6. Update status to ✅ COMPLETED when done
7. Archive completed tasks to `doc/task_history/` if needed

**Status values:**
- 📋 TODO - Not started
- 🔄 IN_PROGRESS - Currently working
- ⏸️ BLOCKED - Waiting on something
- ✅ COMPLETED - Finished
- ❌ CANCELLED - Not proceeding

---

**End of Task Document**
