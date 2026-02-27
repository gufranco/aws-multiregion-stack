.PHONY: help init plan apply destroy localstack-up localstack-down backend-dev backend-build

# =============================================================================
# Configuration
# =============================================================================

# Docker context (override with: make localstack-up DOCKER_CONTEXT=colima-personal)
DOCKER_CONTEXT ?= default

# Environment (dev, staging, prod)
ENV ?= dev

# AWS Region for LocalStack commands
REGION ?= us-east-1

help: ## Show this help message
	@echo 'Usage: make [target] [ENV=dev] [REGION=us-east-1] [DOCKER_CONTEXT=default]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-30s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Variables:'
	@echo '  ENV=$(ENV) (default: dev, options: dev, staging, prod)'
	@echo '  REGION=$(REGION) (default: us-east-1)'
	@echo '  DOCKER_CONTEXT=$(DOCKER_CONTEXT) (default: default)'

# =============================================================================
# Terraform - Environments
# =============================================================================

init: ## Initialize Terraform for current environment
	cd environments/$(ENV) && terraform init

plan: ## Plan Terraform changes for current environment
	cd environments/$(ENV) && terraform plan

apply: ## Apply Terraform changes for current environment
	cd environments/$(ENV) && terraform apply

destroy: ## Destroy infrastructure for current environment
	cd environments/$(ENV) && terraform destroy

output: ## Show Terraform outputs for current environment
	cd environments/$(ENV) && terraform output

# =============================================================================
# Terraform - Module Operations
# =============================================================================

init-modules: ## Initialize all Terraform modules
	@for dir in modules/global modules/region modules/data modules/data-replica modules/security modules/compliance modules/observability modules/resilience modules/finops; do \
		echo "Initializing $$dir..."; \
		(cd $$dir && terraform init -backend=false) || exit 1; \
	done
	@echo "All modules initialized successfully"

validate-modules: ## Validate all Terraform modules
	@for dir in modules/global modules/region modules/data modules/data-replica modules/security modules/compliance modules/observability modules/resilience modules/finops; do \
		echo "Validating $$dir..."; \
		(cd $$dir && terraform validate) || exit 1; \
	done
	@echo "All modules valid"

fmt: ## Format all Terraform files
	terraform fmt -recursive

fmt-check: ## Check Terraform formatting
	terraform fmt -recursive -check

# =============================================================================
# LocalStack - Multi-Region
# =============================================================================

localstack-up: ## Start multi-region LocalStack (6 regions + Postgres + Redis)
	cd localstack && docker --context $(DOCKER_CONTEXT) compose up -d
	@echo ""
	@echo "Waiting for LocalStack regions to be healthy..."
	@sleep 10
	@make localstack-status

localstack-down: ## Stop all LocalStack containers
	cd localstack && docker --context $(DOCKER_CONTEXT) compose down

localstack-clean: ## Stop LocalStack and remove volumes
	cd localstack && docker --context $(DOCKER_CONTEXT) compose down -v

localstack-logs: ## Show LocalStack logs (use REGION=us-east-1 to filter)
	cd localstack && docker --context $(DOCKER_CONTEXT) compose logs -f localstack-$(REGION)

localstack-logs-all: ## Show logs from all LocalStack containers
	cd localstack && docker --context $(DOCKER_CONTEXT) compose logs -f

localstack-status: ## Check status of all LocalStack regions
	@echo "=== LocalStack Multi-Region Status ==="
	@echo ""
	@echo "Region Endpoints:"
	@echo "  us-east-1:      http://localhost:4566"
	@echo "  eu-west-1:      http://localhost:4567"
	@echo "  ap-northeast-1: http://localhost:4568"
	@echo "  sa-east-1:      http://localhost:4569"
	@echo "  me-south-1:     http://localhost:4570"
	@echo "  af-south-1:     http://localhost:4571"
	@echo ""
	@echo "Shared Services:"
	@echo "  PostgreSQL:     localhost:5432"
	@echo "  Redis:          localhost:6379"
	@echo ""
	@echo "Container Status:"
	@cd localstack && docker --context $(DOCKER_CONTEXT) compose ps
	@echo ""
	@echo "Health Checks:"
	@for port in 4566 4567 4568 4569 4570 4571; do \
		status=$$(curl -s http://localhost:$$port/_localstack/health 2>/dev/null | jq -r '.services.sqs // "N/A"' 2>/dev/null || echo "offline"); \
		printf "  Port %s: %s\n" "$$port" "$$status"; \
	done

localstack-init: ## Run init scripts for all regions
	@echo "Running init scripts..."
	@for region in us-east-1 eu-west-1 ap-northeast-1 sa-east-1 me-south-1 af-south-1; do \
		echo "Initializing $$region..."; \
		docker --context $(DOCKER_CONTEXT) exec localstack-$$region bash /etc/localstack/init/ready.d/init.sh 2>/dev/null || true; \
	done

# =============================================================================
# Application Services
# =============================================================================

app-build: ## Build application Docker images
	cd app && docker --context $(DOCKER_CONTEXT) build -t blueprint-api -f api/Dockerfile .
	cd app && docker --context $(DOCKER_CONTEXT) build -t blueprint-worker -f worker/Dockerfile .
	@echo "Images built successfully"

app-up: ## Start application services
	docker --context $(DOCKER_CONTEXT) compose -f docker-compose.yml up -d api worker
	@echo "API: http://localhost:3000"

app-down: ## Stop application services
	docker --context $(DOCKER_CONTEXT) compose -f docker-compose.yml stop api worker

app-logs: ## Show application logs
	docker --context $(DOCKER_CONTEXT) compose -f docker-compose.yml logs -f api worker

app-test: ## Run application tests
	cd app && pnpm test

# =============================================================================
# Full Stack Operations
# =============================================================================

up: localstack-up app-up ## Start everything (LocalStack + App)
	@echo ""
	@echo "=== Stack is running ==="
	@echo "API:           http://localhost:3000"
	@echo "LocalStack:    http://localhost:4566 (us-east-1)"
	@echo "PostgreSQL:    localhost:5432"
	@echo "Redis:         localhost:6379"

down: app-down localstack-down ## Stop everything
	@echo "All services stopped"

restart: down up ## Restart everything

# =============================================================================
# AWS CLI Shortcuts (LocalStack)
# =============================================================================

# Base command for LocalStack AWS CLI
define aws-local
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url=http://localhost:$(1) --region $(2)
endef

# Port mapping for regions
PORT_us-east-1 = 4566
PORT_eu-west-1 = 4567
PORT_ap-northeast-1 = 4568
PORT_sa-east-1 = 4569
PORT_me-south-1 = 4570
PORT_af-south-1 = 4571

list-sqs: ## List SQS queues (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) sqs list-queues

list-sns: ## List SNS topics (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) sns list-topics

list-dynamodb: ## List DynamoDB tables (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) dynamodb list-tables

list-s3: ## List S3 buckets (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) s3 ls

list-secrets: ## List Secrets Manager secrets (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) secretsmanager list-secrets

list-logs: ## List CloudWatch log groups (use REGION=us-east-1)
	$(call aws-local,$(PORT_$(REGION)),$(REGION)) logs describe-log-groups

list-all-regions: ## List SQS queues in all regions
	@echo "=== SQS Queues by Region ==="
	@for region in us-east-1 eu-west-1 ap-northeast-1 sa-east-1 me-south-1 af-south-1; do \
		port=$$(echo "PORT_$$region" | sed 's/-/_/g'); \
		port_num=$$(make -s print-port-$$region 2>/dev/null || echo "4566"); \
		echo ""; \
		echo "$$region:"; \
		AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url=http://localhost:$$port_num --region $$region sqs list-queues 2>/dev/null || echo "  (offline)"; \
	done

print-port-us-east-1:
	@echo 4566
print-port-eu-west-1:
	@echo 4567
print-port-ap-northeast-1:
	@echo 4568
print-port-sa-east-1:
	@echo 4569
print-port-me-south-1:
	@echo 4570
print-port-af-south-1:
	@echo 4571

# =============================================================================
# Database Operations
# =============================================================================

db-connect: ## Connect to PostgreSQL
	docker --context $(DOCKER_CONTEXT) exec -it blueprint-postgres psql -U postgres -d app

db-migrate: ## Run database migrations
	cd app && pnpm db:migrate

db-seed: ## Seed database with sample data
	cd app && pnpm db:seed

db-reset: ## Reset database (drop and recreate)
	docker --context $(DOCKER_CONTEXT) exec -it blueprint-postgres psql -U postgres -c "DROP DATABASE IF EXISTS app; CREATE DATABASE app;"
	@make db-migrate db-seed

redis-cli: ## Connect to Redis CLI
	docker --context $(DOCKER_CONTEXT) exec -it blueprint-redis redis-cli

# =============================================================================
# Testing
# =============================================================================

test: ## Run all tests
	cd app && pnpm test

test-unit: ## Run unit tests
	cd app && pnpm test:unit

test-integration: ## Run integration tests (requires LocalStack)
	cd app && pnpm test:integration

test-e2e: ## Run E2E tests
	cd app && pnpm test:e2e

test-load: ## Run load tests with k6
	cd tests/load && k6 run api-load.js

# =============================================================================
# CI/CD
# =============================================================================

ci-lint: ## Run linters
	terraform fmt -recursive -check
	cd app && pnpm lint

ci-test: ## Run tests for CI
	cd app && pnpm test:ci

ci-build: ## Build for CI
	cd app && pnpm build

ci-security: ## Run security scans
	tfsec .
	cd app && pnpm audit

# =============================================================================
# Setup and Utilities
# =============================================================================

setup: ## Initial project setup
	@echo "Setting up project..."
	@chmod +x localstack/init-scripts/*/*.sh 2>/dev/null || true
	@chmod +x scripts/*.sh 2>/dev/null || true
	@if [ -d "app" ]; then cd app && pnpm install; fi
	@echo "Setup complete!"

clean: ## Clean temporary files
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find . -type f -name "*.zip" -path "*/lambda/*" -delete 2>/dev/null || true
	find . -type f -name "lambda_placeholder.zip" -delete 2>/dev/null || true
	@echo "Cleaned temporary files"

clean-all: clean localstack-clean ## Clean everything including Docker volumes
	@echo "All cleaned"
