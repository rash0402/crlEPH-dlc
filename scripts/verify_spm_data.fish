#!/usr/bin/env fish
# SPM Data Verification Script
# Verifies that backend publishes and viewer receives the same number of agents

echo "============================================================"
echo "SPM Data Flow Verification Script"
echo "============================================================"
echo ""

# Clean up and start fresh
echo "🧹 Cleaning up..."
./scripts/force_cleanup.fish 2>/dev/null
sleep 2
rm -f log/debug_*.log log/detail_viewer.log

# Start simulation in background (provide Enter input automatically)
echo "🚀 Starting simulation..."
echo "" | ./scripts/start_all.fish &

# Wait for simulation to run for a bit
echo "⏳ Waiting 30 seconds for data collection..."
sleep 30

echo ""
echo "============================================================"
echo "📊 Verification Results"
echo "============================================================"
echo ""

# Extract backend publish data
echo "=== Backend (Published) ==="
if test -f log/debug_publish.log
    grep "Publishing" log/debug_publish.log | while read line
        echo "  $line"
    end
else
    echo "  ❌ No publish log found!"
end

echo ""

# Extract viewer receive data  
echo "=== Viewer (Received) ==="
if test -f log/detail_viewer.log
    grep "Received" log/detail_viewer.log | while read line
        echo "  $line"
    end
else
    echo "  ❌ No viewer log found!"
end

echo ""
echo "============================================================"
echo "🔍 Comparing Data..."
echo "============================================================"

# Compare counts
set backend_counts (grep "Publishing" log/debug_publish.log 2>/dev/null | sed 's/.*Publishing \([0-9]*\) agents.*/\1/' | sort -n | uniq)
set viewer_counts (grep "Received" log/detail_viewer.log 2>/dev/null | sed 's/.*Received \([0-9]*\) local_agents.*/\1/' | sort -n | uniq)

echo ""
echo "Backend unique agent counts: $backend_counts"
echo "Viewer unique agent counts: $viewer_counts"
echo ""

# Check if data exists
if test -z "$backend_counts"
    echo "❌ No backend data found!"
    exit 1
end

if test -z "$viewer_counts"
    echo "❌ No viewer data found!"
    exit 1
end

echo "✅ Data flow verification complete!"
echo ""
echo "📝 Manual verification:"
echo "   - Check that Local View shows the correct number of agents"
echo "   - SPM should react to the same agents shown in Local View"
echo ""

# Clean up
echo "🧹 Stopping simulation..."
./scripts/force_cleanup.fish 2>/dev/null

echo "✨ Verification complete!"
