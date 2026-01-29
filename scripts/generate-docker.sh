#!/bin/bash

# ====================================================================
# Generate Docker Files
# ====================================================================
# Generates Dockerfile and build-image.sh from templates
#
# Usage: ./scripts/generate-docker.sh
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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
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

GENERATE_DOCKERFILE=$(yq eval '.docker.generate_dockerfile' "$CONFIG_FILE")
GENERATE_BUILD_SCRIPT=$(yq eval '.docker.generate_build_script' "$CONFIG_FILE")

# Create output directory (outputs/<project-name>/ folder)
OUTPUT_DIR="$PROJECT_ROOT/outputs/$PROJECT_NAME"
mkdir -p "$OUTPUT_DIR"

print_info "Generating Docker files for project type: $PROJECT_TYPE"

# Generate Dockerfile
if [ "$GENERATE_DOCKERFILE" = "true" ]; then
    print_info "Generating Dockerfile..."

    if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        BASE_IMAGE=$(yq eval '.docker.nodejs_server.base_image' "$CONFIG_FILE")
        WORK_DIR=$(yq eval '.docker.nodejs_server.work_dir' "$CONFIG_FILE")
        PORT=$(yq eval '.docker.nodejs_server.port' "$CONFIG_FILE")
        HEALTH_CHECK_PATH=$(yq eval '.docker.nodejs_server.health_check_path' "$CONFIG_FILE")
        HAS_BLOCKCHAIN=$(yq eval '.docker.nodejs_server.has_blockchain' "$CONFIG_FILE")

        # Get build args from docker section
        BUILD_ARGS=$(yq eval '.docker.build_args[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")

        # Build build_args array for JSON
        BUILD_ARGS_JSON="[]"
        if [ -n "$BUILD_ARGS" ]; then
            BUILD_ARGS_JSON="["
            first=true
            for arg in $BUILD_ARGS; do
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
  "BASE_IMAGE": "$BASE_IMAGE",
  "WORK_DIR": "$WORK_DIR",
  "PORT": "$PORT",
  "HEALTH_CHECK_PATH": "$HEALTH_CHECK_PATH",
  "HAS_BLOCKCHAIN": $HAS_BLOCKCHAIN,
  "BUILD_ARGS": $BUILD_ARGS_JSON
}
EOF
)

        # Render template
        python3 "$SCRIPT_DIR/render-template.py" \
            "$PROJECT_ROOT/templates/docker/nodejs-server.Dockerfile.template" \
            "$VARS_JSON" > "$OUTPUT_DIR/Dockerfile"

        print_success "Generated Dockerfile"

    elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        print_warning "NextJS webapp Dockerfile not yet implemented (coming in phase 2)"

    elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
        print_warning "Knex migration Dockerfile not yet implemented (coming in phase 2)"
    fi
else
    print_info "Skipping Dockerfile generation (disabled in config)"
fi

# Generate build-image.sh
if [ "$GENERATE_BUILD_SCRIPT" = "true" ]; then
    print_info "Generating build-image.sh..."

    # Get build args from docker section
    BUILD_ARGS=$(yq eval '.docker.build_args[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")

    # Build build_args array for JSON
    BUILD_ARGS_JSON="[]"
    if [ -n "$BUILD_ARGS" ]; then
        BUILD_ARGS_JSON="["
        first=true
        for arg in $BUILD_ARGS; do
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
  "PROJECT_NAME": "$PROJECT_NAME",
  "AWS_ACCOUNT_ID": "123456789012",
  "AWS_REGION": "$AWS_REGION",
  "ECR_REPOSITORY": "$ECR_REPOSITORY",
  "BUILD_ARGS": $BUILD_ARGS_JSON
}
EOF
)

    # Render template
    python3 "$SCRIPT_DIR/render-template.py" \
        "$PROJECT_ROOT/templates/scripts/build-image.sh.template" \
        "$VARS_JSON" > "$OUTPUT_DIR/build-image.sh"

    chmod +x "$OUTPUT_DIR/build-image.sh"

    print_success "Generated build-image.sh"
else
    print_info "Skipping build-image.sh generation (disabled in config)"
fi

print_success "Docker files generation complete"
