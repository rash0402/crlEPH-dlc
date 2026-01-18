#!/bin/bash
set -e
source "$(dirname "$0")/setup_env.sh"

echo "Syncing local changes to remote ($REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR)..."

# Ensure remote directory exists
ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR"

PROJECT_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"

# Rsync options:
# -a: archive mode
# -v: verbose
# -z: compress
# --delete: delete extraneous files from dest dirs (be careful with this!)
# We exclude data, results, logs to avoid overwriting/deleting valuable data on either side unwantedly
# We also exclude git to save bandwidth and avoid mess
rsync -avz \
    --exclude ".git/" \
    --exclude "data/" \
    --exclude "results/" \
    --exclude "logs/" \
    --exclude "tmp/" \
    --exclude "scripts/remote/.env" \
    --exclude ".DS_Store" \
    "$PROJECT_ROOT/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

echo "Sync up complete."
