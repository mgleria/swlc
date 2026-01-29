#!/bin/bash

# ====================================================================
# Check Docker Readiness
# ====================================================================
# Validates that the project is ready for Docker containerization
#
# Usage: ./scripts/check-docker-ready.sh
# ====================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

errors=0
warnings=0

print_error() {
    echo -e "${RED}✗ $1${NC}"
    ((errors++))
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    ((warnings++))
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "config/project.yaml not found. Run 'make bootstrap' first."
    exit 1
fi

# Read configuration
PROJECT_TYPE=$(yq eval '.project.type' "$CONFIG_FILE")
REPO_PATH=$(yq eval '.project.repository_path' "$CONFIG_FILE")

if [ ! -d "$REPO_PATH" ]; then
    print_error "Repository path does not exist: $REPO_PATH"
    exit 1
fi

echo "Checking Docker readiness for: $REPO_PATH"
echo "Project type: $PROJECT_TYPE"
echo ""

# Check for package.json
if [ ! -f "$REPO_PATH/package.json" ]; then
    print_error "package.json not found"
else
    print_success "package.json exists"

    # Check for required scripts
    cd "$REPO_PATH"

    if [ "$PROJECT_TYPE" = "nodejs-server" ] || [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        if ! grep -q '"build"' package.json; then
            print_warning "No 'build' script found in package.json"
        else
            print_success "'build' script found"
        fi

        if ! grep -q '"start"' package.json; then
            print_warning "No 'start' script found in package.json"
        else
            print_success "'start' script found"
        fi
    fi
fi

# Check for tsconfig.json (TypeScript)
if [ -f "$REPO_PATH/tsconfig.json" ]; then
    print_success "tsconfig.json exists (TypeScript project)"
else
    print_info "No tsconfig.json (JavaScript project or not needed)"
fi

# Check for src directory
if [ -d "$REPO_PATH/src" ]; then
    print_success "src/ directory exists"
else
    print_warning "No src/ directory found"
fi

# Project-specific checks
if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
    # Check for blockchain directory if configured
    HAS_BLOCKCHAIN=$(yq eval '.docker.nodejs_server.has_blockchain' "$CONFIG_FILE")
    if [ "$HAS_BLOCKCHAIN" = "true" ]; then
        if [ -d "$REPO_PATH/blockchain" ]; then
            print_success "blockchain/ directory exists"
        else
            print_error "Blockchain enabled but blockchain/ directory not found"
        fi
    fi

    # Check for server entry point
    if [ -f "$REPO_PATH/src/server.ts" ] || [ -f "$REPO_PATH/src/server.js" ]; then
        print_success "Server entry point found (src/server.*)"
    else
        print_warning "No src/server.ts or src/server.js found"
        print_info "Update Dockerfile CMD if using different entry point"
    fi

elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
    # Check for Next.js specific files
    if [ -f "$REPO_PATH/next.config.js" ] || [ -f "$REPO_PATH/next.config.mjs" ]; then
        print_success "next.config.* found"
    else
        print_error "No next.config.* found - not a Next.js project?"
    fi

    # Check for Next.js output configuration
    if grep -q "output.*standalone" "$REPO_PATH/next.config."* 2>/dev/null; then
        print_success "Next.js configured for standalone output"
    else
        print_warning "Next.js not configured for standalone output"
        print_info "Add to next.config.js: output: 'standalone'"
    fi

elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
    # Check for knexfile
    if [ -f "$REPO_PATH/knexfile.ts" ] || [ -f "$REPO_PATH/knexfile.js" ]; then
        print_success "knexfile.* found"
    else
        print_error "No knexfile.* found"
    fi

    # Check for migrations directory
    if [ -d "$REPO_PATH/migrations" ]; then
        print_success "migrations/ directory exists"
        MIGRATION_COUNT=$(ls -1 "$REPO_PATH/migrations"/*.ts "$REPO_PATH/migrations"/*.js 2>/dev/null | wc -l | tr -d ' ')
        if [ "$MIGRATION_COUNT" -gt 0 ]; then
            print_success "$MIGRATION_COUNT migration file(s) found"
        else
            print_warning "migrations/ directory is empty"
        fi
    else
        print_error "migrations/ directory not found"
    fi
fi

# Check for .dockerignore
if [ -f "$REPO_PATH/.dockerignore" ]; then
    print_success ".dockerignore exists"
else
    print_warning ".dockerignore not found"
    print_info "Consider creating .dockerignore to exclude node_modules, .git, etc."
fi

# Summary
echo ""
echo "=========================================="
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓ Project is Docker-ready!${NC}"
    echo ""
    echo "Next step: make generate-all"
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠ Project is mostly ready with $warnings warning(s)${NC}"
    echo ""
    echo "You can proceed with: make generate-all"
    echo "Address warnings for optimal setup"
    exit 0
else
    echo -e "${RED}✗ Project has $errors error(s) and $warnings warning(s)${NC}"
    echo ""
    echo "Please fix errors before generating Docker files"
    exit 1
fi
