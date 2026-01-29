# SWLC - Software Lifecycle Code Generator

## Project Overview

**Name**: SWLC (Software Lifecycle)
**Purpose**: Automate the creation of CI/CD workflows, Docker configurations, and deployment scripts for software projects. Eliminates boilerplate by generating standardized, best-practice configurations from templates.

**Type**: Code generator / scaffolding tool
**Language**: Bash scripts + Jinja2 templates + Make
**Target**: GitHub Actions workflows, AWS ECS deployments, Docker builds

## Architecture

### Core Components

1. **Templates** (`templates/`) - Jinja2 templates for all generated files
   - `workflows/` - GitHub Actions workflow templates
   - `docker/` - Dockerfile templates
   - `scripts/` - Build and release script templates

2. **Scripts** (`scripts/`) - Generation and validation scripts
   - `bootstrap-project.sh` - Interactive project setup wizard
   - `generate-all.sh` - Master generation script
   - `generate-workflows.sh` - GitHub Actions workflow generator
   - `generate-docker.sh` - Docker file generator
   - `generate-release-script.sh` - Release script generator
   - `generate-secrets-snippets.sh` - GitHub CLI snippets for secrets
   - `validate-config.sh` - Configuration validation
   - `render-template.py` - Jinja2 template renderer
   - `setup-venv.sh` - Python virtual environment setup
   - `activate-venv.sh` - Virtual environment activation helper

3. **Configuration** (`config/`)
   - `project.yaml.template` - Project configuration template (used by bootstrap)

4. **Examples** (`examples/`)
   - `nodejs-server-example.yaml` - Complete example configuration

5. **Outputs** (`outputs/`)
   - `<project-name>/` - Generated files for each project
     - `project.yaml` - Project configuration
     - `.github/workflows/` - Generated workflows
     - `Dockerfile` - Generated Dockerfile
     - `build-image.sh` - Docker build script
     - `scripts/release-prod.mjs` - Release automation script
     - `gh-cli-snippets.sh` - GitHub CLI commands for setup

## Key Design Decisions

### Multi-Project Support
- Each project lives in `outputs/<project-name>/` with its own `project.yaml`
- `PROJECT` environment variable specifies which project to work on
- Auto-discovers first project if `PROJECT` not specified
- Enables managing multiple projects from one SWLC installation

### Template System
- Uses Jinja2 for powerful templating with conditionals and loops
- **Critical**: Proper whitespace control is essential for YAML validity
  - Use `{% if FOO %}` (not `{%- if FOO -%}`) to preserve indentation
  - Only use `-` when explicitly trimming whitespace
- Templates escape shell variables: `${ {{- arg }} }` not `${{{ arg }}}`

### Output Structure
```
outputs/
└── <project-name>/
    ├── project.yaml              # Project configuration
    ├── .github/workflows/
    │   ├── build-and-deploy-development.yml
    │   └── deploy-production-and-release.yml
    ├── Dockerfile
    ├── build-image.sh
    ├── gh-cli-snippets.sh
    └── scripts/
        └── release-prod.mjs
```

### Validation
- `actionlint` validates GitHub Actions workflow syntax
- Configuration validation checks all required fields
- Validation runs automatically during generation

## Configuration Schema

### Project Configuration (`project.yaml`)

```yaml
project:
  name: string                    # Project name (used for folder name)
  type: nodejs-server            # Project type (nodejs-server, nextjs-webapp, knex-migration)
  repository_path: string        # Local repo path (for reference)

  aws:
    region: string               # AWS region
    ecr_repository: string       # ECR repository name

  github:
    org: string                  # GitHub organization
    repo: string                 # GitHub repository
    main_branch: string          # Main branch name (usually 'main')

environments:
  development:
    enabled: boolean
    trigger:
      type: push                 # or 'tag'
      branch: string
      paths_ignore: []           # Optional paths to ignore
    github_environment: string   # GitHub environment name
    deployment:
      enabled: boolean
      ecs_cluster: string
      ecs_service: string
      ecs_task_definition: string
      container_name: string
    migrations:
      enabled: boolean
      container_name: string     # Usually 'migration'
      versions_file: string      # Path to versions file

  production:
    enabled: boolean
    trigger:
      type: tag
      tag_pattern: string        # e.g., 'v*'
    github_environment: string
    deployment:
      enabled: boolean
      ecs_cluster: string
      ecs_service: string
      ecs_task_definition: string
      container_name: string
    migrations:
      enabled: boolean
      container_name: string
      versions_file: string
    validations:
      verify_version: boolean
      verify_branch: boolean
      verify_image_exists: boolean

docker:
  generate_dockerfile: boolean
  generate_build_script: boolean
  platform: string               # e.g., 'linux/amd64'

  # Build arguments passed to Docker build
  build_args:
    - NPM_TOKEN                  # For private npm packages
    # Add more as needed

  nodejs_server:
    base_image: string           # e.g., 'node:22-alpine'
    work_dir: string             # e.g., '/var/api'
    port: number
    health_check_path: string    # e.g., '/health'
    has_blockchain: boolean

release:
  generate_script: boolean
  require_clean_tree: boolean
  require_main_branch: boolean
  verify_package_version: boolean
  prevent_downgrades: boolean
  create_github_release: boolean
```

## Common Commands

### Setup
```bash
# First-time setup (creates Python venv)
make setup

# Bootstrap a new project (interactive)
make bootstrap

# Validate configuration
make validate

# Show current configuration
make show-config
```

### Generation
```bash
# Generate all files for default project
make generate-all

# Generate for specific project
make generate-all PROJECT=myproject

# Generate only workflows
make generate-workflows PROJECT=myproject

# Generate only Docker files
make generate-docker PROJECT=myproject

# Generate only release script
make generate-release-script PROJECT=myproject

# Generate GitHub CLI snippets
make generate-secrets-snippets PROJECT=myproject
```

### Utilities
```bash
# Check if project is Docker-ready
make check-docker-ready

# Clean generated files
make clean
```

## Dependencies

### Required
- `bash` - Shell scripts
- `make` - Build automation
- `python3` - Template rendering
- `yq` - YAML parsing (https://github.com/mikefarah/yq)

### Optional (for validation)
- `actionlint` - GitHub Actions workflow validation (https://github.com/rhysd/actionlint)

### Python Dependencies
- `jinja2>=3.1.0` - Template engine (installed in `.venv`)

## Important Implementation Notes

### Python Virtual Environment
- All generation scripts activate `.venv` automatically
- Scripts use `activate-venv.sh` helper
- Run `make setup` to initialize venv

### Project Discovery
- Scripts automatically find projects in `outputs/*/project.yaml`
- `PROJECT` env var overrides auto-discovery
- Makefile passes `PROJECT` to all scripts

### Template Rendering
- `render-template.py` handles all Jinja2 rendering
- Takes template file path and JSON variables
- Must be run with venv activated

### Build Arguments
- Configured once in `docker.build_args` section
- Automatically propagated to:
  - Dockerfile ARG statements
  - Workflow build steps (as secrets)
  - build-image.sh script
- Common use case: `NPM_TOKEN` for private npm packages

## Known Issues & Gotchas

1. **Jinja2 Whitespace**: Improper whitespace control breaks YAML
   - Symptom: "mapping values are not allowed in this context"
   - Fix: Remove `-` from conditionals unless intentionally trimming

2. **Nested Braces**: Shell variables in templates need spacing
   - Wrong: `${{{ var }}}`
   - Right: `${ {{- var }} }`

3. **Migrations Disabled**: Template references non-existent steps when migrations disabled
   - TODO: Fix conditional step references in templates

4. **ECR Tag Immutability**: Tags cannot be overwritten
   - Use timestamp-based tags: `ci-2026.01.29-1745`

5. **OIDC Provider**: GitHub OIDC provider is account-wide
   - Only create once per AWS account
   - Use `ExistingOIDCProviderArn` parameter if already exists

## Future Enhancements

### Planned Features
- [ ] NextJS webapp support (`nextjs-webapp` type)
- [ ] Knex migration-only projects (`knex-migration` type)
- [ ] Multiple cloud providers (Azure, GCP)
- [ ] Kubernetes deployment targets
- [ ] Terraform/CloudFormation generation
- [ ] CI/CD for other platforms (GitLab, Bitbucket)

### Template Improvements
- [ ] Fix migrations-disabled workflow bug
- [ ] Add more customization options
- [ ] Support for monorepos
- [ ] Multi-stage deployments (staging, etc.)

### Developer Experience
- [ ] Better error messages
- [ ] Dry-run mode
- [ ] Diff mode (show changes before applying)
- [ ] Migration guide for existing projects
- [ ] Web UI for configuration

## Project Structure

```
sw-lifecycle/
├── CLAUDE.md                     # This file
├── README.md                     # User documentation
├── GETTING_STARTED.md           # Quick start guide
├── DEPLOYMENT_CHECKLIST.md      # (if applicable)
├── Makefile                      # Main entry point
├── requirements.txt              # Python dependencies
├── .gitignore                    # Ignores outputs/, .venv/
│
├── config/
│   └── project.yaml.template    # Template for bootstrap
│
├── examples/
│   └── nodejs-server-example.yaml
│
├── scripts/
│   ├── bootstrap-project.sh
│   ├── generate-all.sh
│   ├── generate-workflows.sh
│   ├── generate-docker.sh
│   ├── generate-release-script.sh
│   ├── generate-secrets-snippets.sh
│   ├── validate-config.sh
│   ├── check-docker-ready.sh
│   ├── setup-venv.sh
│   ├── activate-venv.sh
│   └── render-template.py
│
├── templates/
│   ├── workflows/
│   │   ├── nodejs-server-development.yml.template
│   │   └── nodejs-server-production.yml.template
│   ├── docker/
│   │   └── nodejs-server.Dockerfile.template
│   └── scripts/
│       ├── build-image.sh.template
│       └── release-prod.mjs.template
│
├── outputs/                      # Generated files (gitignored)
│   ├── project-1/
│   │   ├── project.yaml
│   │   ├── .github/workflows/
│   │   ├── Dockerfile
│   │   ├── build-image.sh
│   │   └── scripts/
│   └── project-2/
│       └── ...
│
└── .venv/                        # Python venv (gitignored)
```

## Development Workflow

### Adding a New Template Variable
1. Add to `project.yaml` schema (update examples)
2. Read in generation script (e.g., `generate-workflows.sh`)
3. Pass to `render-template.py` in JSON
4. Use in template file
5. Update this CLAUDE.md

### Adding a New Project Type
1. Create new templates in `templates/*/`
2. Add type check in generation scripts
3. Update `bootstrap-project.sh` prompts
4. Update validation in `validate-config.sh`
5. Add example to `examples/`
6. Document in README.md

### Testing Changes
```bash
# Create test project
make bootstrap

# Generate and validate
make generate-all PROJECT=test-project

# Check for workflow syntax errors
actionlint outputs/test-project/.github/workflows/*.yml

# Verify all files generated
ls -la outputs/test-project/
```

## Troubleshooting

### "No module named 'jinja2'"
- Run: `make setup`
- Virtual environment not initialized

### "No project found"
- No `project.yaml` in `outputs/*/`
- Run: `make bootstrap`

### Workflow validation fails
- Check Jinja2 template whitespace
- Run: `actionlint outputs/PROJECT/.github/workflows/*.yml`
- Compare with `*_fixed.yml` files if available

### Config validation fails
- Check all required fields present
- Verify YAML syntax
- Run: `yq eval . outputs/PROJECT/project.yaml`

---

**Last Updated**: 2026-01-29
**Version**: 1.0 (Initial multi-project support)
