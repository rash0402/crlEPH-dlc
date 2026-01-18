#!/bin/bash
set -e
source "$(dirname "$0")/setup_env.sh"

CMD="$@"
if [ -z "$CMD" ]; then
    echo "Usage: $0 \"<command>\""
    echo "Example: $0 \"julia --project=. scripts/run_simulation.jl\""
    exit 1
fi

if [ "$EXECUTION_MODE" == "docker" ]; then
    echo "Running in Docker mode on remote ($REMOTE_HOST)..."
    
    # Check if .julia_cache exists on remote, creates it if not
    # We mount this to /root/.julia inside the container to persist compiled packages (CUDA, etc.)
    ssh -t "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/.julia_cache"
    
    # Note: 
    # -v $(pwd):/root/eph_project : Syncs code changes
    # -v $(pwd)/.julia_cache:/root/.julia : Persists package cache (HUGE speedup)
    ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker run $DOCKER_FLAGS --rm \
        -v \$(pwd):/root/eph_project \
        -v \$(pwd)/.julia_cache:/root/.julia \
        -w /root/eph_project \
        $DOCKER_IMAGE_NAME $CMD"
else
    echo "Running in Direct mode on remote ($REMOTE_HOST)..."
    ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && $CMD"
fi
