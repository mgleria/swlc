#!/bin/bash

# ====================================================================
# Generate GitHub Secrets/Variables Snippets
# ====================================================================
# Generates gh CLI commands to create secrets and variables
#
# Usage: ./scripts/generate-secrets-snippets.sh
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
PROJECT_TYPE=$(yq eval '.project.type' "$CONFIG_FILE")
GITHUB_ORG=$(yq eval '.project.github.org' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.project.github.repo' "$CONFIG_FILE")
ECR_ACCOUNT_ID=$(yq eval '.project.aws.ecr_account_id' "$CONFIG_FILE")

# Create output directory
# Get project name from config
PROJECT_NAME=$(yq eval '.project.name' "$CONFIG_FILE")

# Create output directory (outputs/<project-name>/)
OUTPUT_DIR="${PROJECT_ROOT}/outputs/$PROJECT_NAME"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/gh-cli-snippets.sh"

print_info "Generating GitHub CLI snippets..."

# Start the script
cat > "$OUTPUT_FILE" << 'HEADER'
#!/bin/bash

# ====================================================================
# GitHub Secrets and Variables Setup
# ====================================================================
# This script contains gh CLI commands to create secrets and variables
# for your GitHub repository.
#
# IMPORTANT: Review and customize the values before running!
#
# Usage:
#   1. Review this file and update placeholder values
#   2. Make sure you have gh CLI installed and authenticated
#   3. Run: bash generated/gh-cli-snippets.sh
# ====================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI is not installed"
    echo "Install: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

HEADER

# Add repository info
cat >> "$OUTPUT_FILE" << EOF
REPO="${GITHUB_ORG}/${GITHUB_REPO}"

echo "Setting up secrets and variables for repository: \$REPO"
echo ""
print_warning "This script contains placeholder values that need to be updated!"
print_warning "Please review and edit this file before running."
echo ""

EOF

# Global secrets
if [ "$PROJECT_TYPE" != "knex-migration" ]; then
    cat >> "$OUTPUT_FILE" << 'GLOBAL_SECRETS'
# ====================================================================
# Global Secrets (optional)
# ====================================================================

print_header "Global Secrets"

# NPM_TOKEN (if using private npm packages)
# Uncomment and set if needed:
# echo "Creating NPM_TOKEN secret..."
# gh secret set NPM_TOKEN \
#   --repo "$REPO" \
#   --body "YOUR_NPM_TOKEN_HERE"
# print_success "NPM_TOKEN created"

GLOBAL_SECRETS
fi

# Repository-level variables (not environment-scoped)
if [ "$PROJECT_TYPE" != "knex-migration" ]; then
    cat >> "$OUTPUT_FILE" << EOF
# ====================================================================
# Repository-Level Variables
# ====================================================================

print_header "Repository-Level Variables"

# AWS_ACCOUNT_ID_DEVELOPMENT - needed for cross-account ECR access
# The production workflow pulls images from the development ECR registry,
# so it needs to know the development AWS account ID.
echo "Creating AWS_ACCOUNT_ID_DEVELOPMENT variable (repo-level)..."
gh variable set AWS_ACCOUNT_ID_DEVELOPMENT \\
  --repo "\$REPO" \\
  --body "${ECR_ACCOUNT_ID}"
print_success "AWS_ACCOUNT_ID_DEVELOPMENT=${ECR_ACCOUNT_ID}"

EOF
fi

# Environment-specific secrets and variables
if [ "$PROJECT_TYPE" != "knex-migration" ]; then
    # Development environment
    DEV_ENABLED=$(yq eval '.environments.development.enabled' "$CONFIG_FILE")
    if [ "$DEV_ENABLED" = "true" ]; then
        DEV_CLUSTER=$(yq eval '.environments.development.deployment.ecs_cluster' "$CONFIG_FILE")
        DEV_SERVICE=$(yq eval '.environments.development.deployment.ecs_service' "$CONFIG_FILE")
        DEV_TASK_DEF=$(yq eval '.environments.development.deployment.ecs_task_definition' "$CONFIG_FILE")

        cat >> "$OUTPUT_FILE" << EOF

# ====================================================================
# Development Environment
# ====================================================================

print_header "Development Environment"

# Create development environment (if it doesn't exist)
echo "Creating development environment..."
gh api \\
  --method PUT \\
  -H "Accept: application/vnd.github+json" \\
  "/repos/\$REPO/environments/development" \\
  -f wait_timer=0 \\
  -F prevent_self_review=false \\
  -F reviewers='null' || print_warning "Environment may already exist"

# Secrets
echo "Creating AWS_ROLE_TO_ASSUME secret for development..."
print_warning "UPDATE THIS VALUE: Replace with your actual IAM Role ARN"
print_warning "IMPORTANT: Use IAM format: arn:aws:iam::ACCOUNT:role/ROLE_NAME"
print_warning "           NOT STS format: arn:aws:sts::ACCOUNT:assumed-role/..."
gh secret set AWS_ROLE_TO_ASSUME \\
  --repo "\$REPO" \\
  --env development \\
  --body "arn:aws:iam::123456789012:role/github-actions-development-role"
print_success "AWS_ROLE_TO_ASSUME created"

# Variables
echo "Creating ECS variables for development..."
gh variable set ECS_CLUSTER \\
  --repo "\$REPO" \\
  --env development \\
  --body "$DEV_CLUSTER"
print_success "ECS_CLUSTER=$DEV_CLUSTER"

gh variable set ECS_SERVICE \\
  --repo "\$REPO" \\
  --env development \\
  --body "$DEV_SERVICE"
print_success "ECS_SERVICE=$DEV_SERVICE"

gh variable set ECS_TASK_DEFINITION \\
  --repo "\$REPO" \\
  --env development \\
  --body "$DEV_TASK_DEF"
print_success "ECS_TASK_DEFINITION=$DEV_TASK_DEF"

EOF

        # Add NextJS variables if needed
        if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
            cat >> "$OUTPUT_FILE" << 'NEXTJS_DEV_VARS'
# NextJS build-time variables
print_warning "UPDATE THESE VALUES for NextJS build"
gh variable set NEXT_PUBLIC_API_URL \
  --repo "$REPO" \
  --env development \
  --body "https://api.dev.example.com"
print_success "NEXT_PUBLIC_API_URL set"

gh variable set NEXT_PUBLIC_ENV \
  --repo "$REPO" \
  --env development \
  --body "development"
print_success "NEXT_PUBLIC_ENV set"

NEXTJS_DEV_VARS
        fi

        # Add DOPPLER_TOKEN for nextjs-webapp
        if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
            cat >> "$OUTPUT_FILE" << 'DOPPLER_DEV'
# DOPPLER_TOKEN (for environment variable injection at build time)
echo "Creating DOPPLER_TOKEN secret for development..."
print_warning "UPDATE THIS VALUE: Replace with your actual Doppler service token"
gh secret set DOPPLER_TOKEN \
  --repo "$REPO" \
  --env development \
  --body "dp.st.development.XXXXXXXXXXXX"
print_success "DOPPLER_TOKEN created"

DOPPLER_DEV
        fi
    fi

    # Production environment
    PROD_ENABLED=$(yq eval '.environments.production.enabled' "$CONFIG_FILE")
    if [ "$PROD_ENABLED" = "true" ]; then
        PROD_CLUSTER=$(yq eval '.environments.production.deployment.ecs_cluster' "$CONFIG_FILE")
        PROD_SERVICE=$(yq eval '.environments.production.deployment.ecs_service' "$CONFIG_FILE")
        PROD_TASK_DEF=$(yq eval '.environments.production.deployment.ecs_task_definition' "$CONFIG_FILE")

        cat >> "$OUTPUT_FILE" << EOF

# ====================================================================
# Production Environment
# ====================================================================

print_header "Production Environment"

# Create production environment (if it doesn't exist)
echo "Creating production environment..."
gh api \\
  --method PUT \\
  -H "Accept: application/vnd.github+json" \\
  "/repos/\$REPO/environments/production" \\
  -f wait_timer=0 \\
  -F prevent_self_review=false \\
  -F reviewers='null' || print_warning "Environment may already exist"

# Secrets
echo "Creating AWS_ROLE_TO_ASSUME secret for production..."
print_warning "UPDATE THIS VALUE: Replace with your actual IAM Role ARN"
print_warning "IMPORTANT: Use IAM format: arn:aws:iam::ACCOUNT:role/ROLE_NAME"
print_warning "           NOT STS format: arn:aws:sts::ACCOUNT:assumed-role/..."
gh secret set AWS_ROLE_TO_ASSUME \\
  --repo "\$REPO" \\
  --env production \\
  --body "arn:aws:iam::123456789012:role/github-actions-production-role"
print_success "AWS_ROLE_TO_ASSUME created"

# Variables
echo "Creating ECS variables for production..."
gh variable set ECS_CLUSTER \\
  --repo "\$REPO" \\
  --env production \\
  --body "$PROD_CLUSTER"
print_success "ECS_CLUSTER=$PROD_CLUSTER"

gh variable set ECS_SERVICE \\
  --repo "\$REPO" \\
  --env production \\
  --body "$PROD_SERVICE"
print_success "ECS_SERVICE=$PROD_SERVICE"

gh variable set ECS_TASK_DEFINITION \\
  --repo "\$REPO" \\
  --env production \\
  --body "$PROD_TASK_DEF"
print_success "ECS_TASK_DEFINITION=$PROD_TASK_DEF"

EOF

        # Add NextJS variables if needed
        if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
            cat >> "$OUTPUT_FILE" << 'NEXTJS_PROD_VARS'
# NextJS build-time variables
print_warning "UPDATE THESE VALUES for NextJS build"
gh variable set NEXT_PUBLIC_API_URL \
  --repo "$REPO" \
  --env production \
  --body "https://api.example.com"
print_success "NEXT_PUBLIC_API_URL set"

gh variable set NEXT_PUBLIC_ENV \
  --repo "$REPO" \
  --env production \
  --body "production"
print_success "NEXT_PUBLIC_ENV set"

NEXTJS_PROD_VARS
        fi

        # Add DOPPLER_TOKEN for nextjs-webapp
        if [ "$PROJECT_TYPE" = "nextjs-webapp" ]; then
            cat >> "$OUTPUT_FILE" << 'DOPPLER_PROD'
# DOPPLER_TOKEN (for environment variable injection at build time)
echo "Creating DOPPLER_TOKEN secret for production..."
print_warning "UPDATE THIS VALUE: Replace with your actual Doppler service token"
gh secret set DOPPLER_TOKEN \
  --repo "$REPO" \
  --env production \
  --body "dp.st.production.XXXXXXXXXXXX"
print_success "DOPPLER_TOKEN created"

DOPPLER_PROD
        fi
    fi

    # ECR Repository Policy Documentation
    cat >> "$OUTPUT_FILE" << 'ECR_POLICY_DOCS'
# ====================================================================
# ECR Repository Policy (Cross-Account Access)
# ====================================================================
#
# If your GitHub Actions role lives in a DIFFERENT AWS account than your
# ECR repositories, you need to set a repository policy on each ECR repo
# to allow cross-account access.
#
# CRITICAL: Include ecr:DescribeImages - this is often forgotten and
# causes the "Verify image exists" step to fail in production workflows.
#
# --- API / Server repos (pull-only from production account) ---
# The production account only needs to PULL images that were built and
# pushed by the development account (build-once-and-promote pattern).
#
# aws ecr set-repository-policy \
#   --repository-name YOUR_REPO_NAME \
#   --policy-text '{
#     "Version": "2012-10-17",
#     "Statement": [{
#       "Sid": "AllowCrossAccountPull",
#       "Effect": "Allow",
#       "Principal": {
#         "AWS": "arn:aws:iam::PRODUCTION_ACCOUNT_ID:root"
#       },
#       "Action": [
#         "ecr:GetDownloadUrlForLayer",
#         "ecr:BatchGetImage",
#         "ecr:BatchCheckLayerAvailability",
#         "ecr:DescribeImages"
#       ]
#     }]
#   }'
#
# --- Webapp repos (push+pull from both accounts) ---
# Webapp images are built per-environment (build-per-environment pattern),
# so the production account needs both push AND pull access.
#
# aws ecr set-repository-policy \
#   --repository-name YOUR_REPO_NAME \
#   --policy-text '{
#     "Version": "2012-10-17",
#     "Statement": [{
#       "Sid": "AllowCrossAccountPushPull",
#       "Effect": "Allow",
#       "Principal": {
#         "AWS": "arn:aws:iam::PRODUCTION_ACCOUNT_ID:root"
#       },
#       "Action": [
#         "ecr:GetDownloadUrlForLayer",
#         "ecr:BatchGetImage",
#         "ecr:BatchCheckLayerAvailability",
#         "ecr:DescribeImages",
#         "ecr:PutImage",
#         "ecr:InitiateLayerUpload",
#         "ecr:UploadLayerPart",
#         "ecr:CompleteLayerUpload"
#       ]
#     }]
#   }'
#
# Deployment patterns:
#   nodejs-server: Build-once-and-promote
#     - Dev workflow builds and pushes image to ECR
#     - Prod workflow pulls the SAME image from dev ECR (no rebuild)
#     - Prod ECR policy needs: pull-only
#
#   nextjs-webapp: Build-per-environment
#     - Each environment builds its own image (different build args/env vars)
#     - Both dev and prod push to the SAME ECR registry
#     - Prod ECR policy needs: push+pull
#

ECR_POLICY_DOCS
fi

# Knex migration (simple case - just development environment)
if [ "$PROJECT_TYPE" = "knex-migration" ]; then
    cat >> "$OUTPUT_FILE" << 'KNEX_SECRETS'

# ====================================================================
# Development Environment (for migrations)
# ====================================================================

print_header "Development Environment"

# Create development environment
echo "Creating development environment..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/environments/development" \
  -f wait_timer=0 \
  -F prevent_self_review=false \
  -F reviewers='null' || print_warning "Environment may already exist"

# Secrets
echo "Creating AWS_ROLE_TO_ASSUME secret..."
print_warning "UPDATE THIS VALUE: Replace with your actual IAM Role ARN"
gh secret set AWS_ROLE_TO_ASSUME \
  --repo "$REPO" \
  --env development \
  --body "arn:aws:iam::123456789012:role/github-actions-role"
print_success "AWS_ROLE_TO_ASSUME created"

KNEX_SECRETS
fi

# Footer
cat >> "$OUTPUT_FILE" << 'FOOTER'

# ====================================================================
# Setup Complete
# ====================================================================

print_header "Setup Complete!"

echo "All secrets and variables have been created."
echo ""
echo "Next steps:"
echo "  1. Verify secrets: gh secret list --repo $REPO"
echo "  2. Verify environment secrets: gh secret list --repo $REPO --env development"
echo "  3. Verify variables: gh variable list --repo $REPO --env development"
echo ""
echo "Remember to update placeholder values with your actual configuration!"
echo ""

FOOTER

chmod +x "$OUTPUT_FILE"

print_success "Generated gh CLI snippets: generated/gh-cli-snippets.sh"
print_info "Review and customize the file before running it"
