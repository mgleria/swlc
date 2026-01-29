#!/bin/bash

# ====================================================================
# Generate GitHub Actions Workflows
# ====================================================================
# Generates workflow files from templates based on project configuration
#
# Usage: ./scripts/generate-workflows.sh
# ====================================================================

set -e  # Exit on error

# Colors
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
AWS_REGION=$(yq eval '.project.aws.region' "$CONFIG_FILE")
ECR_REPOSITORY=$(yq eval '.project.aws.ecr_repository' "$CONFIG_FILE")
MAIN_BRANCH=$(yq eval '.project.github.main_branch' "$CONFIG_FILE")
GITHUB_ORG=$(yq eval '.project.github.org' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.project.github.repo' "$CONFIG_FILE")

# Create output directory (outputs/<project-name>/ folder)
OUTPUT_DIR="$PROJECT_ROOT/outputs/$PROJECT_NAME/.github/workflows"
mkdir -p "$OUTPUT_DIR"

print_info "Generating workflows for project type: $PROJECT_TYPE"

# Generate workflows based on project type
if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
    # Generate development workflow
    DEV_ENABLED=$(yq eval '.environments.development.enabled' "$CONFIG_FILE")
    if [ "$DEV_ENABLED" = "true" ]; then
        print_info "Generating development workflow..."

        # Extract development configuration
        DEV_CLUSTER=$(yq eval '.environments.development.deployment.ecs_cluster' "$CONFIG_FILE")
        DEV_SERVICE=$(yq eval '.environments.development.deployment.ecs_service' "$CONFIG_FILE")
        DEV_TASK_DEF=$(yq eval '.environments.development.deployment.ecs_task_definition' "$CONFIG_FILE")
        DEV_CONTAINER=$(yq eval '.environments.development.deployment.container_name' "$CONFIG_FILE")
        DEV_MIGRATIONS=$(yq eval '.environments.development.migrations.enabled' "$CONFIG_FILE")
        DEV_VERSIONS_FILE=$(yq eval '.environments.development.migrations.versions_file' "$CONFIG_FILE")
        # Read build_args from docker section
        DEV_BUILD_ARGS=$(yq eval '.docker.build_args[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")

        # Build JSON for template variables
        MIGRATIONS_CONTAINER="migration"
        if [ "$DEV_MIGRATIONS" = "true" ]; then
            MIGRATIONS_ENABLED="true"
        else
            MIGRATIONS_ENABLED="false"
            DEV_VERSIONS_FILE=""
        fi

        # Build build_args array for JSON
        BUILD_ARGS_JSON="[]"
        if [ -n "$DEV_BUILD_ARGS" ]; then
            BUILD_ARGS_JSON="["
            first=true
            for arg in $DEV_BUILD_ARGS; do
                if [ "$first" = true ]; then
                    BUILD_ARGS_JSON="$BUILD_ARGS_JSON\"$arg\""
                    first=false
                else
                    BUILD_ARGS_JSON="$BUILD_ARGS_JSON, \"$arg\""
                fi
            done
            BUILD_ARGS_JSON="$BUILD_ARGS_JSON]"
        fi

        # Create variables JSON
        VARS_JSON=$(cat <<EOF
{
  "ENV_NAME": "development",
  "ENV_SHORT_NAME": "dev",
  "MAIN_BRANCH": "$MAIN_BRANCH",
  "AWS_REGION": "$AWS_REGION",
  "ECR_REPOSITORY": "$ECR_REPOSITORY",
  "CONTAINER_NAME": "$DEV_CONTAINER",
  "MIGRATIONS_ENABLED": $MIGRATIONS_ENABLED,
  "MIGRATIONS_CONTAINER_NAME": "$MIGRATIONS_CONTAINER",
  "VERSIONS_FILE": "$DEV_VERSIONS_FILE",
  "GITHUB_ENVIRONMENT": "development",
  "BUILD_ARGS": $BUILD_ARGS_JSON
}
EOF
)

        # Render template
        python3 "$SCRIPT_DIR/render-template.py" \
            "$PROJECT_ROOT/templates/workflows/nodejs-server-development.yml.template" \
            "$VARS_JSON" > "$OUTPUT_DIR/build-and-deploy-development.yml"

        print_success "Generated build-and-deploy-development.yml"
    fi

    # Generate production workflow
    PROD_ENABLED=$(yq eval '.environments.production.enabled' "$CONFIG_FILE")
    if [ "$PROD_ENABLED" = "true" ]; then
        print_info "Generating production workflow..."

        # Extract production configuration
        PROD_CLUSTER=$(yq eval '.environments.production.deployment.ecs_cluster' "$CONFIG_FILE")
        PROD_SERVICE=$(yq eval '.environments.production.deployment.ecs_service' "$CONFIG_FILE")
        PROD_TASK_DEF=$(yq eval '.environments.production.deployment.ecs_task_definition' "$CONFIG_FILE")
        PROD_CONTAINER=$(yq eval '.environments.production.deployment.container_name' "$CONFIG_FILE")
        PROD_MIGRATIONS=$(yq eval '.environments.production.migrations.enabled' "$CONFIG_FILE")
        PROD_VERSIONS_FILE=$(yq eval '.environments.production.migrations.versions_file' "$CONFIG_FILE")

        # Build JSON for template variables
        MIGRATIONS_CONTAINER="migration"
        if [ "$PROD_MIGRATIONS" = "true" ]; then
            MIGRATIONS_ENABLED="true"
        else
            MIGRATIONS_ENABLED="false"
            PROD_VERSIONS_FILE=""
        fi

        # Create variables JSON
        VARS_JSON=$(cat <<EOF
{
  "ENV_NAME": "production",
  "ENV_SHORT_NAME": "prod",
  "MAIN_BRANCH": "$MAIN_BRANCH",
  "AWS_REGION": "$AWS_REGION",
  "ECR_REPOSITORY": "$ECR_REPOSITORY",
  "CONTAINER_NAME": "$PROD_CONTAINER",
  "MIGRATIONS_ENABLED": $MIGRATIONS_ENABLED,
  "MIGRATIONS_CONTAINER_NAME": "$MIGRATIONS_CONTAINER",
  "VERSIONS_FILE": "$PROD_VERSIONS_FILE",
  "GITHUB_ENVIRONMENT": "production"
}
EOF
)

        # Render template
        python3 "$SCRIPT_DIR/render-template.py" \
            "$PROJECT_ROOT/templates/workflows/nodejs-server-production.yml.template" \
            "$VARS_JSON" > "$OUTPUT_DIR/deploy-production-and-release.yml"

        print_success "Generated deploy-production-and-release.yml"
    fi

elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
    print_info "NextJS webapp workflows not yet implemented (coming in phase 2)"

elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
    print_info "Knex migration workflows not yet implemented (coming in phase 2)"

else
    echo "Error: Unknown project type: $PROJECT_TYPE"
    exit 1
fi

print_success "Workflow generation complete"
