#!/bin/bash
set -e
source "$(dirname "$0")/setup_env.sh"

echo "Building Docker image '$DOCKER_IMAGE_NAME' on remote ($REMOTE_HOST)..."

ssh -t "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker build -t $DOCKER_IMAGE_NAME ."

echo "Build complete."
