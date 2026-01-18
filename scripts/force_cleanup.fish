#!/usr/bin/env fish
# Force Cleanup Script - EPH v7.2
# Emergency process termination and cache cleanup

echo "🧹 Starting aggressive cleanup (v7.2)..."

# 1. Kill ZMQ communication ports (if used)
echo "  - Killing processes on ports 5555-5556..."
lsof -ti:5555 | xargs kill -9 2>/dev/null
lsof -ti:5556 | xargs kill -9 2>/dev/null

# 2. Kill EPH processes by name (v7.2 scripts)
echo "  - Killing Julia simulation processes..."
pkill -f "julia.*run_simulation_eph.jl" 2>/dev/null
pkill -f "julia.*train_action_vae" 2>/dev/null
pkill -f "julia.*create_dataset_v72" 2>/dev/null

echo "  - Killing Python viewer processes..."
pkill -f "python.*raw_viewer_v72.py" 2>/dev/null
pkill -f "python.*detail_viewer.py" 2>/dev/null

# 3. Nuclear option (use with caution)
if test "$argv[1]" = "--nuclear"
    echo "  ⚠️  NUCLEAR MODE: Killing all Julia/Python processes..."
    killall -9 julia 2>/dev/null
    killall -9 python 2>/dev/null
    killall -9 python3 2>/dev/null
end

# 4. Clean temporary logs
echo "  - Cleaning temporary log files..."
rm -f /tmp/main_viewer.log 2>/dev/null
rm -f /tmp/detail_viewer.log 2>/dev/null
rm -f /tmp/eph_*.log 2>/dev/null

# 5. Clear Julia precompile cache (if corrupted)
if test "$argv[1]" = "--clear-cache"
    echo "  - Clearing Julia precompile cache..."
    rm -rf ~/.julia/compiled/v*/EPH 2>/dev/null
    rm -rf ~/.julia/compiled/v*/crlEPH* 2>/dev/null
end

echo ""
echo "✨ Cleanup complete!"
echo ""
echo "Usage:"
echo "  ./scripts/force_cleanup.fish              # Standard cleanup"
echo "  ./scripts/force_cleanup.fish --nuclear    # Kill all Julia/Python"
echo "  ./scripts/force_cleanup.fish --clear-cache # Also clear Julia cache"
