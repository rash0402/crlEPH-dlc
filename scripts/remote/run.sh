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
    # Note: -t enables TTY which is good for colors/progress bars but might cause issues with some non-interactive scripts
    ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker run $DOCKER_FLAGS --rm -v \$(pwd):/root/eph_project -w /root/eph_project $DOCKER_IMAGE_NAME $CMD"
else
    echo "Running in Direct mode on remote ($REMOTE_HOST)..."
    ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && $CMD"
fi
