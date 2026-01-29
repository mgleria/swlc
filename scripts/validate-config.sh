#!/bin/bash

# ====================================================================
# Validate Configuration
# ====================================================================
# Validates project.yaml configuration
#
# Usage: ./scripts/validate-config.sh
# ====================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

print_error() {
    echo -e "${RED}✗ $1${NC}"
    ((errors++))
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "config/project.yaml not found"
    echo "Run 'make bootstrap' to create it"
    exit 1
fi

print_success "Configuration file exists"

# Validate required fields
validate_field() {
    local path="$1"
    local name="$2"
    local value=$(yq eval "$path" "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        print_error "Missing required field: $name"
        return 1
    fi

    print_success "$name: $value"
    return 0
}

# Validate project section
echo ""
echo "Validating project configuration..."
validate_field '.project.name' "Project name"
validate_field '.project.type' "Project type"
validate_field '.project.repository_path' "Repository path"
validate_field '.project.aws.region' "AWS region"
validate_field '.project.aws.ecr_repository' "ECR repository"
validate_field '.project.github.org' "GitHub org"
validate_field '.project.github.repo' "GitHub repo"
validate_field '.project.github.main_branch' "Main branch"

# Validate project type
PROJECT_TYPE=$(yq eval '.project.type' "$CONFIG_FILE")
if [ "$PROJECT_TYPE" != "nodejs-server" ] && [ "$PROJECT_TYPE" != "nextjs-webapp" ] && [ "$PROJECT_TYPE" != "knex-migration" ]; then
    print_error "Invalid project type: $PROJECT_TYPE (must be nodejs-server, nextjs-webapp, or knex-migration)"
fi

# Validate repository path exists
REPO_PATH=$(yq eval '.project.repository_path' "$CONFIG_FILE")
if [ ! -d "$REPO_PATH" ]; then
    print_warning "Repository path does not exist: $REPO_PATH"
fi

# Validate environments (skip for knex-migration)
if [ "$PROJECT_TYPE" != "knex-migration" ]; then
    echo ""
    echo "Validating environments..."

    # Development
    DEV_ENABLED=$(yq eval '.environments.development.enabled' "$CONFIG_FILE")
    if [ "$DEV_ENABLED" = "true" ]; then
        echo "  Development environment:"
        validate_field '.environments.development.deployment.ecs_cluster' "    ECS cluster"
        validate_field '.environments.development.deployment.ecs_service' "    ECS service"
        validate_field '.environments.development.deployment.ecs_task_definition' "    ECS task definition"
        validate_field '.environments.development.deployment.container_name' "    Container name"
    fi

    # Production
    PROD_ENABLED=$(yq eval '.environments.production.enabled' "$CONFIG_FILE")
    if [ "$PROD_ENABLED" = "true" ]; then
        echo "  Production environment:"
        validate_field '.environments.production.deployment.ecs_cluster' "    ECS cluster"
        validate_field '.environments.production.deployment.ecs_service' "    ECS service"
        validate_field '.environments.production.deployment.ecs_task_definition' "    ECS task definition"
        validate_field '.environments.production.deployment.container_name' "    Container name"
    fi
fi

# Validate Docker configuration
echo ""
echo "Validating Docker configuration..."
validate_field '.docker.generate_dockerfile' "Generate Dockerfile"
validate_field '.docker.generate_build_script' "Generate build script"

if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
    validate_field '.docker.nodejs_server.base_image' "Base image"
    validate_field '.docker.nodejs_server.work_dir' "Work directory"
    validate_field '.docker.nodejs_server.port' "Port"
    validate_field '.docker.nodejs_server.health_check_path' "Health check path"
elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
    validate_field '.docker.nextjs_webapp.base_image' "Base image"
    validate_field '.docker.nextjs_webapp.work_dir' "Work directory"
    validate_field '.docker.nextjs_webapp.port' "Port"
elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
    validate_field '.docker.knex_migration.base_image' "Base image"
    validate_field '.docker.knex_migration.work_dir' "Work directory"
fi

# Summary
echo ""
if [ $errors -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration is valid${NC}"
    exit 0
else
    echo -e "${RED}✗ Configuration has $errors error(s)${NC}"
    exit 1
fi
