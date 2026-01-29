#!/bin/bash

# ====================================================================
# Activate Virtual Environment Helper
# ====================================================================
# This script should be SOURCED (not executed) by other scripts
# to ensure the Python virtual environment is active
#
# Usage (in other scripts):
#   source "$SCRIPT_DIR/activate-venv.sh"
# ====================================================================

# Get the directory of this script (works even when sourced)
if [ -n "$BASH_SOURCE" ]; then
    ACTIVATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    ACTIVATE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

ACTIVATE_PROJECT_ROOT="$(dirname "$ACTIVATE_SCRIPT_DIR")"
VENV_DIR="$ACTIVATE_PROJECT_ROOT/.venv"

# Check if venv exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Please run: ./scripts/setup-venv.sh"
    exit 1
fi

# Activate the virtual environment
source "$VENV_DIR/bin/activate"
