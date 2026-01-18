#!/bin/bash
set -e
source "$(dirname "$0")/setup_env.sh"

echo "Syncing remote results to local ($REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR -> Local)..."

PROJECT_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"

# Pull results
echo "Pulling results..."
rsync -avz \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/results/" \
    "$PROJECT_ROOT/results/"

# Pull logs
echo "Pulling logs..."
rsync -avz \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/logs/" \
    "$PROJECT_ROOT/logs/"

# Pull models (optional, uncomment if needed, or we can make it a flag)
# echo "Pulling models..."
# rsync -avz \
#     "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/models/" \
#     "$PROJECT_ROOT/models/"

echo "Sync down complete."
