#!/bin/bash

# ====================================================================
# Setup Python Virtual Environment
# ====================================================================
# Creates a Python virtual environment and installs dependencies
# This needs to be run once before using the generation scripts
#
# Usage: ./scripts/setup-venv.sh
# ====================================================================

set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_ROOT/.venv"

echo -e "${BLUE}Setting up Python virtual environment...${NC}"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Error: python3 is not installed${NC}"
    echo "Please install Python 3 first"
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Virtual environment already exists at $VENV_DIR${NC}"
    echo "Removing old environment..."
    rm -rf "$VENV_DIR"
fi

echo "Creating virtual environment..."
python3 -m venv "$VENV_DIR"
echo -e "${GREEN}✓ Virtual environment created${NC}"

# Activate virtual environment
echo ""
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip > /dev/null 2>&1
echo -e "${GREEN}✓ pip upgraded${NC}"

# Install dependencies
echo ""
echo "Installing dependencies from requirements.txt..."
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
    pip install -r "$PROJECT_ROOT/requirements.txt"
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${YELLOW}Warning: requirements.txt not found${NC}"
fi

# Deactivate
deactivate

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The virtual environment has been created at:"
echo "  $VENV_DIR"
echo ""
echo "The generation scripts will automatically use this environment."
echo ""
