# Software Lifecycle Bootstrap

Bootstrap GitHub Actions workflows and Docker setup for NodeJS/NextJS projects with AWS ECS deployment.

## Overview

This bootstrap system helps you quickly set up CI/CD workflows for three common use cases:

1. **NodeJS Server** - Backend APIs with runtime environment variables (build-once-and-promote pattern)
2. **NextJS Webapp** - Frontend applications with build-time environment variables
3. **Knex Migration** - Database migration containers (sidecar pattern)

## Features

- **Interactive Bootstrap** - Guided setup with smart defaults
- **Template-Based Generation** - Customizable workflow templates
- **Docker-Ready Check** - Validates project structure before generation
- **GitHub Secrets/Variables Setup** - Auto-generates `gh` CLI snippets
- **Release Automation** - Includes release script with validations
- **Multi-Environment Support** - Development and production workflows

## Quick Start

### 1. Prerequisites

```bash
# Required
brew install yq      # YAML processor
brew install python3 # Python 3 (if not already installed)

# Install Python dependencies
pip3 install jinja2  # Template engine

# Optional (for deployment)
brew install gh      # GitHub CLI (for setting up secrets/variables)
```

### 2. Bootstrap Your Project

```bash
cd infrastructure-templates/sw-lifecycle
make bootstrap
```

This will interactively prompt you for:
- Project name and type
- Repository path
- AWS configuration (region, ECR repository)
- GitHub configuration (org, repo, branch)
- Environment-specific settings (ECS cluster, service names)
- Docker configuration (ports, health checks)
- Migration settings (if applicable)

### 3. Generate All Files

```bash
make generate-all
```

This generates:
- GitHub Actions workflows (`.github/workflows/`)
- Dockerfile
- `build-image.sh` script
- `scripts/release-prod.mjs` (for nodejs-server and nextjs-webapp)
- GitHub secrets/variables setup snippets

### 4. Set Up GitHub Secrets/Variables

```bash
make generate-secrets-snippets
# Review generated/gh-cli-snippets.sh
# Run the commands to create secrets and variables
```

### 5. Commit and Push

```bash
cd /path/to/your/project
git add .github/workflows/ Dockerfile build-image.sh scripts/
git commit -m "Add CI/CD workflows and Docker setup"
git push
```

## Project Types

### NodeJS Server

**Characteristics:**
- Backend API/service
- Runtime environment variables (loaded from files or environment)
- Supports build-once-and-promote pattern
- Optional database migrations (Knex sidecar)

**Generated Workflows:**
- `build-and-deploy-development.yml` - Triggered on push to main
- `deploy-production-and-release.yml` - Triggered on version tags (v*)

**Key Features:**
- Builds single Docker image
- Tags with SHA and timestamp
- Development: deploys immediately after build
- Production: promotes existing image from development
- Verifies image exists in ECR before production deployment
- Creates GitHub release on successful production deployment

### NextJS Webapp

**Characteristics:**
- Frontend application using Next.js
- Build-time environment variables (baked into bundle)
- Cannot use build-once-and-promote (different bundles per environment)

**Generated Workflows:**
- `deploy-development.yaml` - Builds with dev env vars, deploys to dev
- `deploy-production.yaml` - Builds with prod env vars, deploys to prod

**Key Features:**
- Builds separate images for each environment
- Uses `--build-arg` for NEXT_PUBLIC_* variables
- Tags with environment prefix (dev-*, prod-*)
- Validates tag is from main branch before production deployment

### Knex Migration

**Characteristics:**
- Database migration container
- Runs as init/sidecar container before main service
- Short-lived, exits after migrations complete

**Generated Workflows:**
- `build-and-push.yml` - Builds and pushes to ECR on every commit

**Key Features:**
- Simple build and push workflow
- No deployment step (consumed by other services)
- Immutable tags (SHA-based)

## Configuration Reference

See `config/project.yaml.template` for full configuration options.

### Key Configuration Sections

```yaml
project:
  name: myproject
  type: nodejs-server | nextjs-webapp | knex-migration
  repository_path: /path/to/project

  aws:
    region: us-east-1
    ecr_repository: myproject-api

  github:
    org: myorg
    repo: myproject
    main_branch: main

environments:
  development:
    enabled: true
    trigger:
      type: push
      branch: main
    deployment:
      ecs_cluster: development-cluster
      ecs_service: development-api
      # ...

  production:
    enabled: true
    trigger:
      type: tag
      tag_pattern: 'v*'
    validations:
      verify_version: true
      verify_branch: true
      verify_image_exists: true  # For nodejs-server
    # ...

docker:
  generate_dockerfile: true
  generate_build_script: true
  platform: linux/amd64
  # Project-specific settings...

release:
  generate_script: true
  require_clean_tree: true
  require_main_branch: true
  # ...
```

## Directory Structure

```
sw-lifecycle/
├── config/
│   ├── project.yaml.template      # Configuration template
│   └── project.yaml               # Your project config (gitignored)
├── templates/
│   ├── workflows/                 # GitHub Actions workflow templates
│   │   ├── nodejs-server-development.yml.template
│   │   ├── nodejs-server-production.yml.template
│   │   ├── nextjs-webapp-development.yml.template
│   │   ├── nextjs-webapp-production.yml.template
│   │   └── knex-migration.yml.template
│   ├── docker/                    # Dockerfile templates
│   │   ├── nodejs-server.Dockerfile.template
│   │   ├── nextjs-webapp.Dockerfile.template
│   │   └── knex-migration.Dockerfile.template
│   └── scripts/                   # Script templates
│       ├── build-image.sh.template
│       └── release-prod.mjs.template
├── scripts/
│   ├── bootstrap-project.sh       # Interactive bootstrap
│   ├── generate-all.sh            # Generate all files
│   ├── generate-workflows.sh      # Generate workflows only
│   ├── generate-docker.sh         # Generate Docker files only
│   ├── generate-release-script.sh # Generate release script
│   ├── generate-secrets-snippets.sh # Generate gh CLI commands
│   ├── validate-config.sh         # Validate project.yaml
│   └── check-docker-ready.sh      # Validate project structure
├── examples/                      # Example configurations
│   ├── nodejs-server-example.yaml
│   ├── nextjs-webapp-example.yaml
│   └── knex-migration-example.yaml
├── Makefile                       # Main commands
└── README.md                      # This file
```

## GitHub Secrets and Variables

### Required Secrets

All environments need:
- `AWS_ROLE_TO_ASSUME` - IAM Role ARN for GitHub OIDC authentication

Global secrets (optional):
- `NPM_TOKEN` - For private npm packages

### Required Variables

Development environment:
- `ECS_CLUSTER` - ECS cluster name
- `ECS_SERVICE` - ECS service name
- `ECS_TASK_DEFINITION` - ECS task definition name

For NextJS webapp, also:
- `NEXT_PUBLIC_API_URL` - API URL for build-time injection
- `NEXT_PUBLIC_ENV` - Environment name

Production environment: (same as development)

### Setting Up Secrets/Variables

```bash
# Generate snippets
make generate-secrets-snippets

# Review the generated script
cat generated/gh-cli-snippets.sh

# Run the commands (after reviewing)
bash generated/gh-cli-snippets.sh
```

## Workflow Patterns

### Build-Once-and-Promote (NodeJS Server)

1. **Development Flow:**
   ```
   Push to main → Build image → Tag with SHA → Push to ECR → Deploy to dev
   ```

2. **Production Flow:**
   ```
   Create tag v1.0.0 → Verify tag = package.json version
   → Verify tag from main → Verify SHA image exists in ECR
   → Deploy existing image to prod → Create GitHub release
   ```

### Build-Per-Environment (NextJS Webapp)

1. **Development Flow:**
   ```
   Push to main → Build with dev env vars → Tag as dev-* → Deploy to dev
   ```

2. **Production Flow:**
   ```
   Create tag v1.0.0 → Verify tag from main
   → Build with prod env vars → Tag as prod-* and v1.0.0 → Deploy to prod
   ```

### Build-and-Push (Knex Migration)

```
Push to main → Build migration image → Tag with SHA → Push to ECR
```

The migration image is then referenced by nodejs-server workflows using a versions file.

## Release Process

For `nodejs-server` and `nextjs-webapp` projects:

### Using the Release Script

```bash
# From your project directory
npm run release:prod

# With options
npm run release:prod -- --yes       # Skip confirmation
npm run release:prod -- --dry-run   # Validate without creating tag
```

### What the Release Script Does

1. **Validates Environment:**
   - Must be on main branch
   - Working tree must be clean
   - Must be in sync with origin/main

2. **Validates Version:**
   - Reads version from package.json
   - Ensures version > latest released version
   - Ensures tag doesn't already exist

3. **Creates and Pushes Tag:**
   - Creates annotated tag (e.g., v1.0.5)
   - Pushes tag to origin
   - Triggers production deployment workflow

### Manual Release (if needed)

```bash
# Ensure you're on main and up to date
git checkout main
git pull

# Create annotated tag matching package.json version
git tag -a v1.0.5 -m "Release v1.0.5"

# Push tag
git push origin v1.0.5
```

## Troubleshooting

### Docker Build Issues

```bash
# Check if project is Docker-ready
make check-docker-ready

# Test local build
cd /path/to/project
./build-image.sh
```

### Workflow Validation Failures

**"Tag version does not match package.json"**
- Update version in package.json before creating tag
- Use `npm run release:prod` to ensure consistency

**"Tag commit is not an ancestor of main"**
- Ensure tag was created from main branch
- Don't create tags from feature branches

**"API image not found in ECR" (nodejs-server production)**
- Ensure commit was merged to main and built in development first
- Check development workflow ran successfully
- Verify image exists: `aws ecr describe-images --repository-name your-repo --image-ids imageTag=sha-{FULL_SHA}`

**"Migrations image not found in ECR"**
- Build and push migrations image first
- Update `deploy/versions.yml` with correct image URI

### GitHub Secrets/Variables Issues

```bash
# Verify secrets exist
gh secret list --repo org/repo

# Verify environment secrets
gh secret list --repo org/repo --env development

# Verify variables
gh variable list --repo org/repo --env development
```

## Examples

See the `examples/` directory for complete configuration examples:

- `nodejs-server-example.yaml` - API with migrations
- `nextjs-webapp-example.yaml` - Frontend with build-time vars
- `knex-migration-example.yaml` - Migration container

## Advanced Usage

### Customizing Templates

Templates use Jinja2-like syntax with placeholders:

```yaml
name: Build and Deploy to {{ ENV_NAME | capitalize }}

env:
  AWS_REGION: {{ AWS_REGION }}
  ECR_REPOSITORY: {{ ECR_REPOSITORY }}
```

To customize:
1. Edit templates in `templates/workflows/`, `templates/docker/`, or `templates/scripts/`
2. Regenerate files: `make generate-all`

### Adding Custom Build Args

Edit `config/project.yaml`:

```yaml
environments:
  development:
    build_args:
      - NPM_TOKEN
      - CUSTOM_BUILD_VAR
      - ANOTHER_VAR
```

### Multi-Stage Dockerfiles

The generated Dockerfiles use multi-stage builds:
- Stage 1: Dependencies
- Stage 2: Build
- Stage 3: Production runtime

Customize stages in templates as needed for your project.

## Best Practices

1. **Use the Release Script** - Automates validations and ensures consistency
2. **Immutable Tags** - Never reuse ECR image tags
3. **Build Once for NodeJS** - Promote same image to production
4. **Environment Variables** - Use GitHub Environments for secrets/variables
5. **Migrations as Init Containers** - Run migrations before main service starts
6. **Health Checks** - Include health check endpoints in your applications
7. **Concurrency Control** - Workflows use concurrency groups to prevent parallel deploys

## Contributing

To improve this bootstrap system:

1. Add new templates in `templates/`
2. Update generation scripts in `scripts/`
3. Document changes in README.md
4. Test with example projects

## Support

For issues or questions:
1. Check troubleshooting section
2. Review example configurations
3. Validate configuration: `make validate`
4. Check Docker readiness: `make check-docker-ready`

## License

UNLICENSED - Internal use only
