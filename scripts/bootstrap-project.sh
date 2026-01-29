#!/bin/bash

# ====================================================================
# Software Lifecycle Bootstrap Script
# ====================================================================
# This script initializes GitHub Actions workflows and Docker setup
# for NodeJS/NextJS projects with AWS ECS deployment.
#
# It will:
# - Prompt for project configuration
# - Generate config/project.yaml
# - Generate GitHub Actions workflows
# - Generate Dockerfile and build scripts
# - Generate release scripts
# - Generate gh CLI snippets for secrets/variables
#
# Usage: ./scripts/bootstrap-project.sh
# ====================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ====================================================================
# Helper Functions
# ====================================================================

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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [${default}]: )" value
        value=${value:-$default}
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}: )" value
    fi

    eval "$var_name='$value'"
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"

    if [ "$default" = "y" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [Y/n]: )" response
        response=${response:-y}
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC} [y/N]: )" response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy] ]]
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")

    echo ""
    echo -e "${CYAN}${prompt}${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    echo ""

    while true; do
        read -p "$(echo -e ${CYAN})Choice [1-${#options[@]}]: $(echo -e ${NC})" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return
        else
            echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#options[@]}.${NC}"
        fi
    done
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing_tools=()

    # Check for required tools
    command -v yq >/dev/null 2>&1 || missing_tools+=("yq")
    command -v python3 >/dev/null 2>&1 || missing_tools+=("python3")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        echo "Please install missing tools and try again."
        echo "  yq: https://github.com/mikefarah/yq or 'brew install yq'"
        echo "  python3: brew install python3"
        exit 1
    fi

    # Check for Python jinja2 module
    if ! python3 -c "import jinja2" 2>/dev/null; then
        print_error "Python jinja2 module not found"
        echo ""
        echo "Install with:"
        echo "  pip3 install jinja2"
        echo ""
        echo "Or create a virtual environment:"
        echo "  python3 -m venv .venv"
        echo "  source .venv/bin/activate"
        echo "  pip install jinja2"
        exit 1
    fi

    print_success "Prerequisites met"
}

# ====================================================================
# Configuration Gathering
# ====================================================================

gather_project_config() {
    print_header "Project Configuration"

    echo "Let's configure your project's software lifecycle automation."
    echo ""

    # Project name
    while true; do
        prompt_input "Project name (lowercase, alphanumeric, hyphens)" "" PROJECT_NAME
        if [[ "$PROJECT_NAME" =~ ^[a-z0-9-]+$ ]]; then
            break
        else
            print_error "Invalid project name. Use only lowercase letters, numbers, and hyphens."
        fi
    done

    # Project type
    echo ""
    echo -e "${CYAN}Select project type:${NC}"
    echo "  1. nodejs-server"
    echo "  2. nextjs-webapp"
    echo "  3. knex-migration"
    echo ""
    while true; do
        read -p "Enter choice [1-3]: " choice
        case $choice in
            1) PROJECT_TYPE="nodejs-server"; break;;
            2) PROJECT_TYPE="nextjs-webapp"; break;;
            3) PROJECT_TYPE="knex-migration"; break;;
            *) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}";;
        esac
    done
    print_success "Selected: $PROJECT_TYPE"

    # Repository path
    echo ""
    prompt_input "Repository path (where to generate files)" "../${PROJECT_NAME}" REPO_PATH

    # Check if repository exists
    if [ ! -d "$REPO_PATH" ]; then
        print_warning "Repository path does not exist: $REPO_PATH"
        if prompt_yes_no "Do you want to create it?" "n"; then
            mkdir -p "$REPO_PATH"
            print_success "Created directory: $REPO_PATH"
        else
            print_error "Cannot proceed without valid repository path"
            exit 1
        fi
    fi

    # AWS Configuration
    echo ""
    print_info "AWS Configuration (for ECR and ECS deployment)"
    prompt_input "AWS Region" "us-east-1" AWS_REGION
    prompt_input "ECR Repository name" "${PROJECT_NAME}" ECR_REPOSITORY

    # GitHub Configuration
    echo ""
    print_info "GitHub Configuration"
    prompt_input "GitHub organization/username" "" GITHUB_ORG
    prompt_input "GitHub repository name" "$PROJECT_NAME" GITHUB_REPO
    prompt_input "Main branch name" "main" MAIN_BRANCH

    print_success "Project configuration gathered"
}

gather_environment_config() {
    local env_name="$1"
    local env_upper=$(echo "$env_name" | tr '[:lower:]' '[:upper:]')

    print_header "${env_upper} Environment Configuration"

    # For migration projects, skip environment config
    if [ "$PROJECT_TYPE" = "knex-migration" ]; then
        print_info "Migration projects don't use environment-specific configuration"
        return
    fi

    # Enable environment
    if prompt_yes_no "Enable ${env_name} environment?" "y"; then
        eval "ENV_${env_upper}_ENABLED=true"
    else
        eval "ENV_${env_upper}_ENABLED=false"
        return
    fi

    # Trigger type
    if [ "$env_name" = "production" ]; then
        print_info "Production environment will use tag-based releases (v*)"
        eval "ENV_${env_upper}_TRIGGER=tag"
    else
        eval "ENV_${env_upper}_TRIGGER=push"
    fi

    # ECS Configuration
    echo ""
    print_info "ECS Configuration for ${env_name}"

    # Use project name as prefix to avoid naming collisions
    local short_env="dev"
    if [ "$env_name" = "production" ]; then
        short_env="prod"
    fi

    local default_cluster="${PROJECT_NAME}-${short_env}-cluster"
    local default_service="${PROJECT_NAME}-${short_env}-api"
    if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        default_service="${PROJECT_NAME}-${short_env}-webapp"
    fi
    local default_task_def="$default_service"

    prompt_input "ECS Cluster name" "$default_cluster" "ENV_${env_upper}_ECS_CLUSTER"
    prompt_input "ECS Service name" "$default_service" "ENV_${env_upper}_ECS_SERVICE"
    prompt_input "ECS Task Definition name" "$default_task_def" "ENV_${env_upper}_ECS_TASK_DEFINITION"

    # Container name
    if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        eval "ENV_${env_upper}_CONTAINER_NAME=api"
    elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        eval "ENV_${env_upper}_CONTAINER_NAME=webapp"
    fi

    # Migrations (only for nodejs-server)
    if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        echo ""
        if prompt_yes_no "Does this project use database migrations (knex)?" "n"; then
            eval "ENV_${env_upper}_MIGRATIONS_ENABLED=true"
            prompt_input "Path to versions file (e.g., deploy/versions.yml)" "deploy/versions.yml" "ENV_${env_upper}_VERSIONS_FILE"
        else
            eval "ENV_${env_upper}_MIGRATIONS_ENABLED=false"
        fi
    fi

    # Build args (for nextjs-webapp or if using private npm packages)
    if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        echo ""
        print_info "Next.js projects require build-time environment variables"
        eval "ENV_${env_upper}_BUILD_ARGS=\"NPM_TOKEN NEXT_PUBLIC_API_URL NEXT_PUBLIC_ENV\""
    elif [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        echo ""
        if prompt_yes_no "Do you use private NPM packages?" "n"; then
            eval "ENV_${env_upper}_BUILD_ARGS=\"NPM_TOKEN\""
        else
            eval "ENV_${env_upper}_BUILD_ARGS=\"\""
        fi
    fi

    print_success "${env_upper} environment configured"
}

gather_docker_config() {
    print_header "Docker Configuration"

    # Check if Docker files already exist
    if [ -f "$REPO_PATH/Dockerfile" ]; then
        print_warning "Dockerfile already exists in repository"
        if ! prompt_yes_no "Overwrite existing Dockerfile?" "n"; then
            GENERATE_DOCKERFILE=false
            print_info "Skipping Dockerfile generation"
        else
            GENERATE_DOCKERFILE=true
        fi
    else
        GENERATE_DOCKERFILE=true
    fi

    # Check if build script exists
    if [ -f "$REPO_PATH/build-image.sh" ]; then
        print_warning "build-image.sh already exists in repository"
        if ! prompt_yes_no "Overwrite existing build-image.sh?" "n"; then
            GENERATE_BUILD_SCRIPT=false
            print_info "Skipping build-image.sh generation"
        else
            GENERATE_BUILD_SCRIPT=true
        fi
    else
        GENERATE_BUILD_SCRIPT=true
    fi

    # Project-specific Docker configuration
    if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        prompt_input "Application port" "3020" DOCKER_PORT
        prompt_input "Health check path" "/health" DOCKER_HEALTH_PATH

        # Check for blockchain sub-project
        if [ -d "$REPO_PATH/blockchain" ]; then
            print_info "Detected blockchain sub-project"
            if prompt_yes_no "Include blockchain compilation in Docker build?" "y"; then
                HAS_BLOCKCHAIN=true
            else
                HAS_BLOCKCHAIN=false
            fi
        else
            HAS_BLOCKCHAIN=false
        fi
    elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        prompt_input "Application port" "3000" DOCKER_PORT
        prompt_input "Health check path" "/api/health" DOCKER_HEALTH_PATH
    elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
        DOCKER_PORT=""
        DOCKER_HEALTH_PATH=""
    fi

    print_success "Docker configuration complete"
}

gather_release_config() {
    print_header "Release Configuration"

    # Only for nodejs-server and nextjs-webapp
    if [ "$PROJECT_TYPE" = "knex-migration" ]; then
        print_info "Migration projects don't use release scripts"
        GENERATE_RELEASE_SCRIPT=false
        return
    fi

    # Check if release script exists
    if [ -f "$REPO_PATH/scripts/release-prod.mjs" ]; then
        print_warning "scripts/release-prod.mjs already exists in repository"
        if ! prompt_yes_no "Overwrite existing release-prod.mjs?" "n"; then
            GENERATE_RELEASE_SCRIPT=false
            print_info "Skipping release script generation"
            return
        fi
    fi

    GENERATE_RELEASE_SCRIPT=true
    print_success "Will generate release script"
}

# ====================================================================
# File Generation
# ====================================================================

generate_project_yaml() {
    print_header "Generating project.yaml"

    local template_file="${PROJECT_ROOT}/config/project.yaml.template"
    local output_dir="${PROJECT_ROOT}/outputs/${PROJECT_NAME}"
    local output_file="${output_dir}/project.yaml"

    # Create project output directory
    mkdir -p "$output_dir"

    if [ -f "$output_file" ]; then
        if ! prompt_yes_no "outputs/${PROJECT_NAME}/project.yaml already exists. Overwrite?" "n"; then
            print_warning "Skipping project.yaml generation"
            return
        fi
        mv "$output_file" "${output_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backed up existing project.yaml"
    fi

    # Build YAML file from gathered configuration
    cat > "$output_file" << EOF
# Software Lifecycle Configuration
# Generated on $(date)

project:
  name: ${PROJECT_NAME}
  type: ${PROJECT_TYPE}
  repository_path: ${REPO_PATH}

  aws:
    region: ${AWS_REGION}
    ecr_repository: ${ECR_REPOSITORY}

  github:
    org: ${GITHUB_ORG}
    repo: ${GITHUB_REPO}
    main_branch: ${MAIN_BRANCH}

EOF

    # Add environments configuration (skip for migration projects)
    if [ "$PROJECT_TYPE" != "knex-migration" ]; then
        cat >> "$output_file" << EOF
environments:
EOF

        # Development environment
        if [ "${ENV_DEVELOPMENT_ENABLED}" = "true" ]; then
            cat >> "$output_file" << EOF
  development:
    enabled: true

    trigger:
      type: ${ENV_DEVELOPMENT_TRIGGER}
      branch: ${MAIN_BRANCH}
      paths_ignore:
        - '.github/**'

    github_environment: development

    deployment:
      enabled: true
      ecs_cluster: ${ENV_DEVELOPMENT_ECS_CLUSTER}
      ecs_service: ${ENV_DEVELOPMENT_ECS_SERVICE}
      ecs_task_definition: ${ENV_DEVELOPMENT_ECS_TASK_DEFINITION}
      container_name: ${ENV_DEVELOPMENT_CONTAINER_NAME}

EOF

            # Add migrations if enabled
            if [ "${ENV_DEVELOPMENT_MIGRATIONS_ENABLED}" = "true" ]; then
                cat >> "$output_file" << EOF
    migrations:
      enabled: true
      container_name: migration
      versions_file: ${ENV_DEVELOPMENT_VERSIONS_FILE}

EOF
            fi

            # Add build args if present
            if [ -n "${ENV_DEVELOPMENT_BUILD_ARGS}" ]; then
                cat >> "$output_file" << EOF
    build_args:
EOF
                for arg in ${ENV_DEVELOPMENT_BUILD_ARGS}; do
                    echo "      - $arg" >> "$output_file"
                done
                echo "" >> "$output_file"
            fi
        fi

        # Production environment
        if [ "${ENV_PRODUCTION_ENABLED}" = "true" ]; then
            cat >> "$output_file" << EOF
  production:
    enabled: true

    trigger:
      type: ${ENV_PRODUCTION_TRIGGER}
      tag_pattern: 'v*'

    github_environment: production

    deployment:
      enabled: true
      ecs_cluster: ${ENV_PRODUCTION_ECS_CLUSTER}
      ecs_service: ${ENV_PRODUCTION_ECS_SERVICE}
      ecs_task_definition: ${ENV_PRODUCTION_ECS_TASK_DEFINITION}
      container_name: ${ENV_PRODUCTION_CONTAINER_NAME}

EOF

            # Add migrations if enabled
            if [ "${ENV_PRODUCTION_MIGRATIONS_ENABLED}" = "true" ]; then
                cat >> "$output_file" << EOF
    migrations:
      enabled: true
      container_name: migration
      versions_file: ${ENV_PRODUCTION_VERSIONS_FILE}

EOF
            fi

            # Add build args if present
            if [ -n "${ENV_PRODUCTION_BUILD_ARGS}" ]; then
                cat >> "$output_file" << EOF
    build_args:
EOF
                for arg in ${ENV_PRODUCTION_BUILD_ARGS}; do
                    echo "      - $arg" >> "$output_file"
                done
                echo "" >> "$output_file"
            fi

            # Add production validations
            cat >> "$output_file" << EOF
    validations:
      verify_version: true
      verify_branch: true
EOF
            if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
                echo "      verify_image_exists: true" >> "$output_file"
            fi
            echo "" >> "$output_file"
        fi
    fi

    # Add Docker configuration
    cat >> "$output_file" << EOF
docker:
  generate_dockerfile: ${GENERATE_DOCKERFILE}
  generate_build_script: ${GENERATE_BUILD_SCRIPT}
  platform: linux/amd64

EOF

    # Project-specific Docker settings
    if [ "$PROJECT_TYPE" = "nodejs-server" ]; then
        cat >> "$output_file" << EOF
  nodejs_server:
    base_image: node:22-alpine
    work_dir: /var/api
    port: ${DOCKER_PORT}
    health_check_path: ${DOCKER_HEALTH_PATH}
    has_blockchain: ${HAS_BLOCKCHAIN}

EOF
    elif [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
        cat >> "$output_file" << EOF
  nextjs_webapp:
    base_image: node:22-alpine
    work_dir: /var/webapp
    port: ${DOCKER_PORT}
    health_check_path: ${DOCKER_HEALTH_PATH}
    output: standalone

EOF
    elif [ "$PROJECT_TYPE" = "knex-migration" ]; then
        cat >> "$output_file" << EOF
  knex_migration:
    base_image: node:22-alpine
    work_dir: /app

EOF
    fi

    # Add release configuration
    if [ "$PROJECT_TYPE" != "knex-migration" ]; then
        cat >> "$output_file" << EOF
release:
  generate_script: ${GENERATE_RELEASE_SCRIPT}
  require_clean_tree: true
  require_main_branch: true
  verify_package_version: true
  prevent_downgrades: true
  create_github_release: true
EOF
    fi

    print_success "Generated outputs/${PROJECT_NAME}/project.yaml"
    print_info "Review and customize outputs/${PROJECT_NAME}/project.yaml as needed"
}

# ====================================================================
# Main Execution
# ====================================================================

main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════╗"
    echo "║   Software Lifecycle Bootstrap            ║"
    echo "║   GitHub Actions & Docker Setup           ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Prerequisites
    check_prerequisites

    # Gather configuration
    gather_project_config

    # Environment-specific configuration
    if [ "$PROJECT_TYPE" != "knex-migration" ]; then
        gather_environment_config "development"
        gather_environment_config "production"
    fi

    gather_docker_config
    gather_release_config

    # Generate project.yaml
    generate_project_yaml

    # Final instructions
    print_header "Bootstrap Complete!"

    echo -e "${GREEN}Your software lifecycle configuration has been initialized!${NC}"
    echo ""
    echo "Files created:"
    echo "  ✓ outputs/${PROJECT_NAME}/project.yaml - Project configuration"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. ${YELLOW}Review the generated configuration:${NC}"
    echo "   cat outputs/${PROJECT_NAME}/project.yaml"
    echo ""
    echo "2. ${YELLOW}Generate all project files:${NC}"
    echo "   make generate-all"
    echo ""
    echo "   This will create:"
    echo "   - GitHub Actions workflows in ${REPO_PATH}/.github/workflows/"
    if [ "$GENERATE_DOCKERFILE" = "true" ]; then
        echo "   - Dockerfile in ${REPO_PATH}/"
    fi
    if [ "$GENERATE_BUILD_SCRIPT" = "true" ]; then
        echo "   - build-image.sh in ${REPO_PATH}/"
    fi
    if [ "$GENERATE_RELEASE_SCRIPT" = "true" ]; then
        echo "   - scripts/release-prod.mjs in ${REPO_PATH}/scripts/"
    fi
    echo "   - GitHub CLI snippets for secrets/variables"
    echo ""
    echo "3. ${YELLOW}Set up GitHub secrets and variables:${NC}"
    echo "   make generate-secrets-snippets"
    echo "   # Review generated/gh-cli-snippets.sh and run the commands"
    echo ""
    echo "4. ${YELLOW}Test Docker build locally:${NC}"
    echo "   cd ${REPO_PATH}"
    echo "   ./build-image.sh"
    echo ""
    echo "5. ${YELLOW}Commit and push workflows:${NC}"
    echo "   git add .github/workflows/"
    echo "   git commit -m 'Add GitHub Actions workflows'"
    echo "   git push"
    echo ""
    echo "Available commands:"
    echo "  make help               - Show all available commands"
    echo "  make generate-all       - Generate all files"
    echo "  make validate           - Validate configuration"
    echo "  make check-docker-ready - Verify Docker setup"
    echo ""
    echo -e "${GREEN}Happy deploying! 🚀${NC}"
}

# Run main function
main
