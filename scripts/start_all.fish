#!/usr/bin/env fish
# EPH All-in-One Launcher (Fish shell)
# Starts backend and both viewers in separate terminal windows (macOS)

# Check if libtorch is set up
if not set -q LIBTORCH_ROOT
    echo "❌ LIBTORCH_ROOT not found. Please run: source scripts/setup_libtorch.fish"
    exit 1
end

set PROJECT_DIR (dirname (dirname (realpath (status -f))))
# Define Julia binary path directly
set JULIA_BIN "$HOME/.juliaup/bin/julia"

echo "============================================================"
echo "EPH All-in-One Launcher (macOS)"
echo "============================================================"
echo ""
echo "📂 Project: $PROJECT_DIR"
echo ""
echo "This will start 3 background processes:"
echo "  1. Julia Backend"
echo "  2. Main Viewer (4-group display)"
echo "  3. Detail Viewer (SPM + metrics)"
echo ""
echo "Press Enter to continue, or Ctrl+C to cancel..."
read

echo "📦 Starting components..."
echo ""

# Start Julia backend in background
echo "1️⃣  Starting Julia backend..."
cd $PROJECT_DIR
$JULIA_BIN --project=. scripts/run_simulation.jl > /tmp/backend.log 2>&1 &
set BACKEND_PID $last_pid
echo "   Backend PID: $BACKEND_PID"

# Wait a moment for backend to initialize
sleep 2

# Start Python viewers in background
echo "2️⃣  Starting Main Viewer..."
~/local/venv/bin/python3 viewer/main_viewer.py > /tmp/main_viewer.log 2>&1 &
set MAIN_VIEWER_PID $last_pid
echo "   Main Viewer PID: $MAIN_VIEWER_PID"

echo "3️⃣  Starting Detail Viewer..."
~/local/venv/bin/python3 viewer/detail_viewer.py > /tmp/detail_viewer.log 2>&1 &
set DETAIL_VIEWER_PID $last_pid
echo "   Detail Viewer PID: $DETAIL_VIEWER_PID"

echo ""
echo "✅ All components started!"
echo ""
echo "📊 Process IDs:"
echo "   Backend:       $BACKEND_PID"
echo "   Main Viewer:   $MAIN_VIEWER_PID"
echo "   Detail Viewer: $DETAIL_VIEWER_PID"
echo ""
echo "📝 Viewer logs:"
echo "   Main:   /tmp/main_viewer.log"
echo "   Detail: /tmp/detail_viewer.log"
echo ""
echo "⚠️  To stop all processes:"
echo "   kill $BACKEND_PID $MAIN_VIEWER_PID $DETAIL_VIEWER_PID"
echo ""
echo "Press Ctrl+C to stop (this will NOT stop the background processes)"
echo "Waiting for processes..."

# Wait for any process to finish
wait
