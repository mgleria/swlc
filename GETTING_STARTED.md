# Getting Started with Software Lifecycle Bootstrap

This guide will walk you through bootstrapping GitHub Actions workflows for your NodeJS/NextJS project.

## Prerequisites

1. **Install Required Tools:**
   ```bash
   # yq - YAML processor (required)
   brew install yq

   # gh - GitHub CLI (optional, for setting up secrets/variables)
   brew install gh

   # Python 3 with Jinja2 (for template rendering)
   pip3 install jinja2
   ```

2. **Prepare Your Project:**
   - Your project should have a `package.json`
   - For TypeScript projects: `tsconfig.json`
   - Source code in `src/` directory
   - Build script configured in package.json

## Quick Start (NodeJS Server)

### Step 1: Bootstrap Configuration

```bash
cd infrastructure-templates/sw-lifecycle
make bootstrap
```

This interactive script will prompt you for:
- **Project name**: `myapi` (lowercase, alphanumeric, hyphens)
- **Project type**: Select `nodejs-server`
- **Repository path**: `/path/to/your/api`
- **AWS region**: `us-east-1`
- **ECR repository**: `myapi`
- **GitHub org/repo**: `myorg/myapi`
- **Main branch**: `main`

For each environment (development, production):
- ECS cluster, service, and task definition names
- Whether to enable database migrations
- Build arguments (e.g., NPM_TOKEN for private packages)

Docker configuration:
- Application port (default: 3020)
- Health check path (default: /health)
- Whether project has blockchain sub-project

### Step 2: Validate Configuration

```bash
make validate
```

This checks that all required fields are present and valid.

### Step 3: Check Docker Readiness

```bash
make check-docker-ready
```

This validates your project structure:
- ✓ package.json with build/start scripts
- ✓ src/ directory
- ✓ TypeScript configuration (if applicable)
- ✓ Server entry point (src/server.ts)
- ✓ Migrations directory (if enabled)

### Step 4: Generate All Files

```bash
make generate-all
```

This generates:
1. **GitHub Actions workflows** in `<your-repo>/.github/workflows/`:
   - `build-and-deploy-development.yml`
   - `deploy-production-and-release.yml`

2. **Dockerfile** in `<your-repo>/`

3. **Build script** in `<your-repo>/build-image.sh`

4. **Release script** in `<your-repo>/scripts/release-prod.mjs`

5. **GitHub CLI snippets** in `generated/gh-cli-snippets.sh`

### Step 5: Set Up GitHub Secrets/Variables

```bash
# Review the generated script
cat generated/gh-cli-snippets.sh

# Edit placeholder values (AWS Role ARNs, etc.)
vim generated/gh-cli-snippets.sh

# Run the script
bash generated/gh-cli-snippets.sh
```

The script creates:

**Development Environment:**
- Secret: `AWS_ROLE_TO_ASSUME`
- Variables: `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION`

**Production Environment:**
- Secret: `AWS_ROLE_TO_ASSUME`
- Variables: `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION`

**Global Secrets** (optional):
- `NPM_TOKEN` - if using private npm packages

### Step 6: Test Docker Build Locally

```bash
cd /path/to/your/api

# Set environment variables if needed
export NPM_TOKEN="your-npm-token"

# Build the image
./build-image.sh
```

### Step 7: Create Migrations Version File (if using migrations)

If you enabled migrations, create `deploy/versions.yml`:

```yaml
migrations_image: "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapi-knex:sha-abc123"
```

This file tracks which migration image version to use.

### Step 8: Commit and Push

```bash
cd /path/to/your/api

git add .github/workflows/ Dockerfile build-image.sh scripts/
git commit -m "Add CI/CD workflows and Docker setup"
git push
```

This triggers the development workflow which will:
1. Build Docker image
2. Tag with SHA and timestamp
3. Push to ECR
4. Deploy to development ECS

### Step 9: Release to Production

When ready for production:

```bash
# Update version in package.json
npm version patch  # or minor, or major

# Run release script (validates and creates tag)
npm run release:prod

# Or with options
npm run release:prod -- --dry-run  # Test without creating tag
npm run release:prod -- --yes      # Skip confirmation
```

The release script:
1. Validates you're on main branch
2. Checks working tree is clean
3. Verifies version > latest released version
4. Creates annotated tag (e.g., v1.0.5)
5. Pushes tag to origin

The production workflow then:
1. Verifies tag matches package.json version
2. Verifies tag is from main branch
3. Verifies API image exists in ECR
4. Verifies migrations image exists (if enabled)
5. Deploys to production ECS
6. Creates GitHub release

## Understanding the Workflows

### Development Workflow

**Trigger**: Push to main branch

**Steps**:
1. Checkout code
2. Compute image tags (SHA, timestamp)
3. Configure AWS credentials (OIDC)
4. Login to ECR
5. Build Docker image with build args
6. Push images to ECR
7. Read migrations version (if enabled)
8. Download current ECS task definition
9. Update task definition with new image
10. Update task definition with migrations image (if enabled)
11. Deploy to ECS

**Image Tags**:
- `ci-2026.01.28-1234-abc1234` - Timestamp + short SHA
- `sha-abc1234567890...` - Full commit SHA

### Production Workflow

**Trigger**: Push tag matching `v*` pattern

**Steps**:
1. Checkout code with full history
2. Resolve tag to commit SHA
3. **Verify tag matches package.json version**
4. **Verify tag is from main branch**
5. Configure AWS credentials
6. **Verify API image exists in ECR** (build-once-and-promote)
7. **Verify migrations image exists** (if enabled)
8. Download current ECS task definition
9. Update task definition (reuse existing images)
10. Deploy to ECS
11. Create GitHub release

**Key Validations**:
- Tag version must match package.json
- Tag must be ancestor of main branch
- API image must already exist in ECR
- Migrations image must exist in ECR

## Build-Once-and-Promote Pattern

NodeJS servers support the build-once-and-promote pattern:

1. **Development**: Build image once when merged to main
2. **Production**: Deploy same image (no rebuild)

Benefits:
- Same artifact tested in dev is deployed to prod
- Faster production deployments
- No risk of build-time differences

## Migrations Pattern

If your API uses database migrations (Knex):

1. **Build migration image** separately (knex-migration project)
2. **Tag migration image** with SHA
3. **Update `deploy/versions.yml`** in API repo with image URI
4. **Workflows use sidecar pattern**: Migration container runs before API container

Example versions file:
```yaml
migrations_image: "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapi-knex:sha-abc123def456"
```

## Troubleshooting

### "Tag version does not match package.json"

**Cause**: Tag was created manually without updating package.json

**Solution**:
```bash
# Always use the release script
npm run release:prod

# Or update package.json first
npm version patch
git push
git tag -a v1.0.5 -m "Release v1.0.5"
git push origin v1.0.5
```

### "Tag commit is not an ancestor of main"

**Cause**: Tag was created from a branch other than main

**Solution**:
- Only create tags from main branch
- Merge your branch to main first
- Then create the tag

### "API image not found in ECR"

**Cause**: Commit was never built (not merged to main, or build failed)

**Solution**:
1. Ensure commit is on main branch
2. Check that development workflow ran successfully
3. Verify image exists:
   ```bash
   aws ecr describe-images \
     --repository-name myapi \
     --image-ids imageTag=sha-YOUR_COMMIT_SHA
   ```

### "Migrations image not found in ECR"

**Cause**: Migration image hasn't been built, or versions.yml has wrong URI

**Solution**:
1. Build migration image first (from knex-migration project)
2. Update `deploy/versions.yml` with correct image URI
3. Commit and push the updated versions.yml
4. Create new release tag

## Next Steps

- **Phase 2**: NextJS webapp support (build-per-environment pattern)
- **Phase 3**: Knex migration project support
- **Customize templates**: Edit templates in `templates/` directory
- **Add more environments**: Extend configuration for staging, etc.

## Support

- Check `README.md` for full documentation
- Review `examples/` directory for complete configurations
- Run `make help` to see all available commands
- Validate config: `make validate`
- Check Docker readiness: `make check-docker-ready`

## Summary

You've now set up a complete CI/CD pipeline for your NodeJS server with:
- ✅ Automated builds on every commit to main
- ✅ Automated deployments to development
- ✅ Safe, validated production releases with tags
- ✅ Build-once-and-promote pattern
- ✅ Database migration support (optional)
- ✅ GitHub releases for tracking
- ✅ Comprehensive validation and error checking

Happy deploying! 🚀
