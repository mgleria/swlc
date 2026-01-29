#!/bin/bash

# ====================================================================
# Generate Release Script
# ====================================================================
# Generates scripts/release-prod.mjs from template
#
# Usage: ./scripts/generate-release-script.sh
# ====================================================================

set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get project name from environment or find first project
if [ -z "$PROJECT" ]; then
    PROJECT=$(find "$PROJECT_ROOT/outputs" -maxdepth 2 -name "project.yaml" | head -1 | xargs dirname | xargs basename 2>/dev/null)
fi

if [ -z "$PROJECT" ]; then
    echo "Error: No project found. Run 'make bootstrap' first or specify PROJECT=name"
    exit 1
fi

CONFIG_FILE="${PROJECT_ROOT}/outputs/$PROJECT/project.yaml"

# Activate Python virtual environment
source "$SCRIPT_DIR/activate-venv.sh"

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config/project.yaml not found"
    exit 1
fi

# Read configuration
PROJECT_NAME=$(yq eval '.project.name' "$CONFIG_FILE")
PROJECT_TYPE=$(yq eval '.project.type' "$CONFIG_FILE")
GENERATE_SCRIPT=$(yq eval '.release.generate_script' "$CONFIG_FILE")
MAIN_BRANCH=$(yq eval '.project.github.main_branch' "$CONFIG_FILE")
GITHUB_ORG=$(yq eval '.project.github.org' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.project.github.repo' "$CONFIG_FILE")

# Only generate for nodejs-server and nextjs-webapp
if [ "$PROJECT_TYPE" = "knex-migration" ]; then
    print_info "Skipping release script (not applicable for migration projects)"
    exit 0
fi

if [ "$GENERATE_SCRIPT" != "true" ]; then
    print_info "Skipping release script generation (disabled in config)"
    exit 0
fi

print_info "Generating release script..."

# Create output directory (outputs/<project-name>/scripts)
OUTPUT_DIR="$PROJECT_ROOT/outputs/$PROJECT_NAME/scripts"
mkdir -p "$OUTPUT_DIR"

# Create variables JSON
VARS_JSON=$(cat <<EOF
{
  "MAIN_BRANCH": "$MAIN_BRANCH",
  "GITHUB_ORG": "$GITHUB_ORG",
  "GITHUB_REPO": "$GITHUB_REPO"
}
EOF
)

# Render template
python3 "$SCRIPT_DIR/render-template.py" \
    "$PROJECT_ROOT/templates/scripts/release-prod.mjs.template" \
    "$VARS_JSON" > "$OUTPUT_DIR/release-prod.mjs"

chmod +x "$OUTPUT_DIR/release-prod.mjs"

print_success "Generated scripts/release-prod.mjs"
