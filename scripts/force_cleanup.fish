#!/usr/bin/env fish

echo "🧹 Starting aggressively cleanup..."

# Kill specific ports
lsof -ti:5555 | xargs kill -9
lsof -ti:5556 | xargs kill -9

# Kill processes by name
pkill -f "julia.*run_simulation.jl"
pkill -f "python.*viewer"

# Nuclear option
killall -9 julia
killall -9 python

# Clean logs
rm -f log/debug_spm.log
rm -f log/debug_filter.log
rm -f /tmp/main_viewer.log
rm -f /tmp/detail_viewer.log

# Clear Julia precompile cache for EPH
rm -rf ~/.julia/compiled/v*/EPH

echo "✨ Cleanup complete. All Julia/Python processes should be dead."
