.PHONY: help setup bootstrap validate generate-workflows generate-docker generate-all clean

# Load project configuration
# If PROJECT is specified, use it. Otherwise, find the first project in outputs/
PROJECT ?= $(shell find outputs -maxdepth 2 -name "project.yaml" | head -1 | xargs dirname | xargs basename 2>/dev/null)
CONFIG_FILE := outputs/$(PROJECT)/project.yaml
-include .env

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# ====================================================================
# Help
# ====================================================================

help: ## Show this help message
	@echo "$(BLUE)Software Lifecycle Bootstrap Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Initial Setup:$(NC)"
	@echo "  make setup                     - Set up Python virtual environment (run once)"
	@echo "  make bootstrap                 - Initialize new project (interactive)"
	@echo "  make validate                  - Validate project configuration"
	@echo ""
	@echo "$(GREEN)Generation Commands:$(NC)"
	@echo "  make generate-all              - Generate all workflows, Docker files, and scripts"
	@echo "  make generate-workflows        - Generate GitHub Actions workflows only"
	@echo "  make generate-docker           - Generate Dockerfile and build script only"
	@echo "  make generate-release-script   - Generate release-prod.mjs script"
	@echo "  make generate-secrets-snippets - Generate gh CLI snippets for secrets/variables"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make check-docker-ready        - Validate if project is Docker-ready"
	@echo "  make clean                     - Clean generated files"
	@echo "  make show-config               - Display current project configuration"
	@echo ""

# ====================================================================
# Initial Setup
# ====================================================================

setup: ## Set up Python virtual environment
	@echo "$(BLUE)Setting up Python virtual environment...$(NC)"
	@./scripts/setup-venv.sh

bootstrap: ## Initialize new project from template
	@echo "$(BLUE)Starting software lifecycle bootstrap...$(NC)"
	@./scripts/bootstrap-project.sh

validate: ## Validate project configuration
	@echo "$(BLUE)Validating project configuration...$(NC)"
	@if [ -z "$(PROJECT)" ]; then \
		echo "$(YELLOW)No project found. Run 'make bootstrap' first or specify PROJECT=name$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "$(YELLOW)$(CONFIG_FILE) not found. Run 'make bootstrap' first.$(NC)"; \
		exit 1; \
	fi
	@PROJECT=$(PROJECT) ./scripts/validate-config.sh
	@echo "$(GREEN)✓ Configuration is valid$(NC)"

# ====================================================================
# Generation Commands
# ====================================================================

generate-all: validate ## Generate all workflows, Docker files, and scripts
	@echo "$(BLUE)Generating all project files for $(PROJECT)...$(NC)"
	@PROJECT=$(PROJECT) ./scripts/generate-all.sh
	@echo "$(GREEN)✓ All files generated successfully$(NC)"

generate-workflows: validate ## Generate GitHub Actions workflows
	@echo "$(BLUE)Generating GitHub Actions workflows...$(NC)"
	@PROJECT=$(PROJECT) ./scripts/generate-workflows.sh
	@echo "$(GREEN)✓ Workflows generated$(NC)"

generate-docker: validate ## Generate Dockerfile and build script
	@echo "$(BLUE)Generating Docker files...$(NC)"
	@PROJECT=$(PROJECT) ./scripts/generate-docker.sh
	@echo "$(GREEN)✓ Docker files generated$(NC)"

generate-release-script: validate ## Generate release-prod.mjs script
	@echo "$(BLUE)Generating release script...$(NC)"
	@PROJECT=$(PROJECT) ./scripts/generate-release-script.sh
	@echo "$(GREEN)✓ Release script generated$(NC)"

generate-secrets-snippets: validate ## Generate gh CLI snippets
	@echo "$(BLUE)Generating GitHub secrets/variables snippets...$(NC)"
	@PROJECT=$(PROJECT) ./scripts/generate-secrets-snippets.sh
	@echo "$(GREEN)✓ Snippets generated$(NC)"

# ====================================================================
# Utilities
# ====================================================================

check-docker-ready: ## Check if project is Docker-ready
	@./scripts/check-docker-ready.sh

show-config: ## Display current project configuration
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "$(YELLOW)outputs/project.yaml not found$(NC)"; \
		exit 1; \
	fi
	@cat $(CONFIG_FILE)

clean: ## Clean generated files
	@echo "$(BLUE)Cleaning generated files...$(NC)"
	@rm -rf generated/
	@find . -name "*.backup.*" -delete
	@echo "$(GREEN)✓ Cleaned generated files$(NC)"
