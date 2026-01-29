#!/bin/bash

# ====================================================================
# Generate All Files
# ====================================================================
# This script generates all workflows, Docker files, and scripts
# from templates based on config/project.yaml
#
# Usage: ./scripts/generate-all.sh
# ====================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# ====================================================================
# Main Execution
# ====================================================================

print_header "Generating All Files"

# Validate configuration first
echo "Validating configuration..."
if ! "$SCRIPT_DIR/validate-config.sh"; then
    print_error "Configuration validation failed"
    exit 1
fi
print_success "Configuration is valid"

# Generate workflows
echo ""
print_info "Generating GitHub Actions workflows..."
"$SCRIPT_DIR/generate-workflows.sh"
print_success "Workflows generated"

# Validate workflows with actionlint if available
if command -v actionlint &> /dev/null; then
    echo ""
    print_info "Validating workflow syntax with actionlint..."

    # Get project name for output path
    PROJECT_NAME=$(yq eval '.project.name' "$CONFIG_FILE")

    if actionlint "$PROJECT_ROOT/outputs/$PROJECT_NAME/.github/workflows/"*.yml 2>&1; then
        print_success "Workflow validation passed"
    else
        print_error "Workflow validation failed - please review syntax errors above"
        exit 1
    fi
else
    print_info "Skipping workflow validation (actionlint not installed)"
fi

# Generate Docker files
echo ""
print_info "Generating Docker files..."
"$SCRIPT_DIR/generate-docker.sh"
print_success "Docker files generated"

# Generate release script
echo ""
print_info "Generating release script..."
"$SCRIPT_DIR/generate-release-script.sh"
print_success "Release script generated"

# Generate secrets snippets
echo ""
print_info "Generating GitHub secrets/variables snippets..."
"$SCRIPT_DIR/generate-secrets-snippets.sh"
print_success "Secrets snippets generated"

# Summary
print_header "Generation Complete!"

echo -e "${GREEN}All files have been generated successfully!${NC}"
echo ""
echo "Generated files:"
echo "  ✓ GitHub Actions workflows"
echo "  ✓ Dockerfile and build script"
echo "  ✓ Release script"
echo "  ✓ GitHub CLI snippets"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo "1. Review the generated files in your repository"
echo "2. Set up GitHub secrets and variables:"
echo "   bash generated/gh-cli-snippets.sh"
echo ""
echo "3. Test Docker build locally:"
echo "   cd \$(yq eval '.project.repository_path' config/project.yaml)"
echo "   ./build-image.sh"
echo ""
echo "4. Commit and push to trigger workflows:"
echo "   git add .github/workflows/ Dockerfile build-image.sh scripts/"
echo "   git commit -m 'Add CI/CD workflows and Docker setup'"
echo "   git push"
echo ""
