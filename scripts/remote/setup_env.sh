#!/bin/bash
# Load environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please copy scripts/remote/.env.template to scripts/remote/.env and configure it."
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [ -z "$REMOTE_HOST" ]; then
    echo "Error: REMOTE_HOST not set in .env"
    exit 1
fi

if [ -z "$REMOTE_USER" ]; then
    echo "Error: REMOTE_USER not set in .env"
    exit 1
fi

if [ -z "$REMOTE_DIR" ]; then
    echo "Error: REMOTE_DIR not set in .env"
    exit 1
fi

# Default docker image name if not set
if [ -z "$DOCKER_IMAGE_NAME" ]; then
    DOCKER_IMAGE_NAME="crleph-dlc"
fi
