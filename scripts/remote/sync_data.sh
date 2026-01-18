#!/bin/bash
set -e
source "$(dirname "$0")/setup_env.sh"

echo "Syncing local DATA to remote ($REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR)..."
echo "WARNING: This may take a long time for large datasets."

# Ensure remote data directory exists
ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/data"

PROJECT_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"

# Rsync data directory
# Note: We sync the contents of data/ to remote data/
rsync -avz --progress \
    "$PROJECT_ROOT/data/" \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/data/"

echo "Data sync complete."
