#!/bin/bash

# ====================================================================
# Generate Doppler Webhook Setup Script
# ====================================================================
# Generates curl commands to create Doppler webhooks that trigger
# the syncDopplerToS3 GitHub Actions workflow on secret changes.
#
# Pre-requisites:
#   - Doppler Personal Token (workplace-scoped)
#     Generate from: Doppler Dashboard → Account → Personal Tokens
#   - GitHub PAT (fine-grained) with permissions:
#     - Actions: Read and Write
#     - Metadata: Read
#     Scoped to the target repository
#
# Usage: ./scripts/generate-doppler-webhooks.sh
# ====================================================================

set -e

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
    echo "Error: $CONFIG_FILE not found"
    exit 1
fi

# Check if doppler section exists
DOPPLER_PROJECT=$(yq eval '.doppler.project' "$CONFIG_FILE")
if [ "$DOPPLER_PROJECT" = "null" ] || [ -z "$DOPPLER_PROJECT" ]; then
    echo "Error: No doppler configuration found in $CONFIG_FILE"
    echo "Add a 'doppler' section with project name and configs."
    exit 1
fi

# Read configuration
GITHUB_ORG=$(yq eval '.project.github.org' "$CONFIG_FILE")
GITHUB_REPO=$(yq eval '.project.github.repo' "$CONFIG_FILE")
MAIN_BRANCH=$(yq eval '.project.github.main_branch' "$CONFIG_FILE")
SYNC_WORKFLOW=$(yq eval '.doppler.sync_workflow' "$CONFIG_FILE")
PROJECT_NAME=$(yq eval '.project.name' "$CONFIG_FILE")
CONFIG_COUNT=$(yq eval '.doppler.configs | length' "$CONFIG_FILE")

# Create output directory
OUTPUT_DIR="${PROJECT_ROOT}/outputs/$PROJECT_NAME"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/doppler-webhooks.sh"

print_info "Generating Doppler webhook commands..."

# Write the script header
cat > "$OUTPUT_FILE" << 'HEADER'
#!/bin/bash

# ====================================================================
# Doppler Webhook Setup
# ====================================================================
# Creates Doppler webhooks that automatically trigger the
# syncDopplerToS3 GitHub Actions workflow when secrets change.
#
# Pre-requisites:
#   - Doppler Personal Token (workplace-scoped)
#     Generate from: Doppler Dashboard → Account → Personal Tokens
#   - GitHub PAT (fine-grained) with permissions:
#     - Actions: Read and Write
#     - Metadata: Read
#     Scoped to the target repository
#
# Usage:
#   1. Set DOPPLER_TOKEN and GITHUB_PAT below
#   2. Review the generated commands
#   3. Run: bash doppler-webhooks.sh
# ====================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info()    { echo -e "${CYAN}ℹ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }

# ── Tokens ──────────────────────────────────────────────────────────
# IMPORTANT: Set these before running!
DOPPLER_TOKEN="${DOPPLER_TOKEN:-}"
GITHUB_PAT="${GITHUB_PAT:-}"

if [ -z "$DOPPLER_TOKEN" ]; then
    print_error "DOPPLER_TOKEN is not set"
    echo "  Export it:  export DOPPLER_TOKEN=dp.pt.xxxxx"
    echo "  Generate from: Doppler Dashboard → Account → Personal Tokens"
    exit 1
fi

if [ -z "$GITHUB_PAT" ]; then
    print_error "GITHUB_PAT is not set"
    echo "  Export it:  export GITHUB_PAT=github_pat_xxxxx"
    echo "  Create a fine-grained token with Actions:write and Metadata:read"
    exit 1
fi

HEADER

# Write project-specific variables
cat >> "$OUTPUT_FILE" << EOF
# ── Project Configuration ───────────────────────────────────────────
GH_ORG="${GITHUB_ORG}"
GH_REPO="${GITHUB_REPO}"
MAIN_BRANCH="${MAIN_BRANCH}"
DOPPLER_PROJECT="${DOPPLER_PROJECT}"
SYNC_WORKFLOW="${SYNC_WORKFLOW}"

DISPATCH_URL="https://api.github.com/repos/\${GH_ORG}/\${GH_REPO}/actions/workflows/\${SYNC_WORKFLOW}/dispatches"
WEBHOOK_API="https://api.doppler.com/v3/webhooks?project=\${DOPPLER_PROJECT}"

echo ""
print_info "Creating Doppler webhooks for project: \${DOPPLER_PROJECT}"
print_info "Target repo: \${GH_ORG}/\${GH_REPO}"
print_info "Workflow: \${SYNC_WORKFLOW}"
echo ""

EOF

# Generate a webhook command for each Doppler config
for i in $(seq 0 $((CONFIG_COUNT - 1))); do
    CONFIG_NAME=$(yq eval ".doppler.configs[$i].name" "$CONFIG_FILE")
    GH_ENV=$(yq eval ".doppler.configs[$i].github_environment" "$CONFIG_FILE")

    cat >> "$OUTPUT_FILE" << BLOCK
# ── ${DOPPLER_PROJECT} / ${CONFIG_NAME} → ${GH_ENV} ──
echo "Creating webhook: ${CONFIG_NAME} → ${GH_ENV}..."
JSON_BODY=\$(cat << ENDJSON
{
  "name": "${GITHUB_REPO} sync ${CONFIG_NAME}",
  "url": "\$DISPATCH_URL",
  "authentication": {"type": "Bearer", "token": "\$GITHUB_PAT"},
  "payload": "{\"ref\": \"\$MAIN_BRANCH\", \"inputs\": {\"target\": \"${GH_ENV}\"}}",
  "enableConfigs": ["${CONFIG_NAME}"]
}
ENDJSON
)

RESPONSE=\$(curl -s -w "\n%{http_code}" -X POST "\${WEBHOOK_API}" \\
  -H "Authorization: Bearer \$DOPPLER_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d "\$JSON_BODY")

HTTP_CODE=\$(echo "\$RESPONSE" | tail -1)
if [ "\$HTTP_CODE" = "200" ] || [ "\$HTTP_CODE" = "201" ]; then
    print_success "Webhook created: ${CONFIG_NAME} → ${GH_ENV}"
else
    print_error "Failed to create webhook (HTTP \$HTTP_CODE)"
    echo "\$RESPONSE" | head -n -1
fi
echo ""

BLOCK
done

# Footer
cat >> "$OUTPUT_FILE" << 'FOOTER'
# ── Verify ──────────────────────────────────────────────────────────
echo "---"
print_info "Verify webhooks in Doppler Dashboard → Project → Webhooks tab"
print_info "Test by changing a non-critical secret and checking GitHub Actions"

FOOTER

chmod +x "$OUTPUT_FILE"

print_success "Generated Doppler webhook script: $OUTPUT_FILE"
print_info "Set DOPPLER_TOKEN and GITHUB_PAT, then run: bash $OUTPUT_FILE"
