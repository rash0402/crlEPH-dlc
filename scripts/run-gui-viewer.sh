#!/bin/bash
set -e

echo "Starting Python EPH Viewer..."

# Activate Virtual Environment
source ~/local/venv/bin/activate

cd "$(dirname "$0")/.."
export PYTHONPATH=.
python viewer.py
