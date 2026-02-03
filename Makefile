# Include configuration file
-include config.mk

# Try to get the commit hash from 1) git 2) fallback.
LAST_COMMIT := $(or $(shell git rev-parse --short HEAD 2> /dev/null),"dev")

# Try to get the semver from 1) git 2) fallback.
VERSION := $(or $(MAILPIT_VERSION),$(shell git describe --tags --abbrev=0 2> /dev/null),"v0.0.0")

BUILDSTR := ${VERSION} (\#${LAST_COMMIT} $(shell date -u +"%Y-%m-%dT%H:%M:%S%z"))

# Docker configuration (can be overridden in config.mk)
AWS_ACCOUNT_ID ?= 123456789012
AWS_REGION ?= ap-southeast-1
DOCKER_REGISTRY := ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
ECR_REPO := techinasia-tools/mailpit
DOCKER_IMAGE := ${DOCKER_REGISTRY}/${ECR_REPO}

# Multi-architecture build configuration
PLATFORMS ?= linux/amd64,linux/arm64
BUILDER_NAME ?= mailpit-builder

BIN := mailpit
FRONTEND_DEPS = \
	package.json \
	package-lock.json \
	esbuild.config.mjs \
	eslint.config.js \
	$(shell find server/ui-src -type f)

SRC := $(shell find . -type f -name "*.go")

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Configuration:'
	@echo '  Copy config.mk.sample to config.mk and update AWS_ACCOUNT_ID'

.PHONY: config
config: ## Create config.mk from sample
	@if [ -f config.mk ]; then \
		echo "config.mk already exists"; \
	else \
		cp config.mk.sample config.mk; \
		echo "Created config.mk from config.mk.sample"; \
		echo "Please update AWS_ACCOUNT_ID in config.mk"; \
	fi

.PHONY: build
build: $(BIN) ## Build the mailpit binary

# Build the backend to ./mailpit
$(BIN): $(SRC) go.mod go.sum
	CGO_ENABLED=0 go build -o ${BIN} -ldflags="-s -w -X 'github.com/axllent/mailpit/config.Version=${VERSION}' -X 'github.com/axllent/mailpit/config.Repo=github.com/axllent/mailpit'" .

.PHONY: run
run: ## Run mailpit locally
	go run -ldflags="-X 'github.com/axllent/mailpit/config.Version=${VERSION}'" .

.PHONY: test
test: ## Run Go tests
	go test ./...

.PHONY: clean
clean: ## Clean build artifacts
	rm -f $(BIN)

# Docker targets
.PHONY: docker-build
docker-build: ## Build Docker image
	docker build \
		--build-arg VERSION=${VERSION} \
		-t ${ECR_REPO}:${VERSION} \
		-t ${ECR_REPO}:latest \
		.
	@echo "Built image: ${ECR_REPO}:${VERSION}"

.PHONY: docker-build-tag
docker-build-tag: ## Build and tag Docker image for ECR
	docker build \
		--build-arg VERSION=${VERSION} \
		-t ${DOCKER_IMAGE}:${VERSION} \
		-t ${DOCKER_IMAGE}:latest \
		.
	@echo "Built and tagged image: ${DOCKER_IMAGE}:${VERSION}"

# Multi-architecture build targets
.PHONY: buildx-setup
buildx-setup: ## Setup buildx builder for multi-arch builds
	@if ! docker buildx inspect ${BUILDER_NAME} > /dev/null 2>&1; then \
		echo "Creating buildx builder: ${BUILDER_NAME}"; \
		docker buildx create --name ${BUILDER_NAME} --driver docker-container --bootstrap --use; \
	else \
		echo "Buildx builder ${BUILDER_NAME} already exists"; \
		docker buildx use ${BUILDER_NAME}; \
	fi
	docker buildx inspect --bootstrap

.PHONY: buildx-remove
buildx-remove: ## Remove buildx builder
	docker buildx rm ${BUILDER_NAME} || true

.PHONY: docker-build-multiarch
docker-build-multiarch: buildx-setup ## Build multi-architecture Docker image (amd64, arm64)
	docker buildx build \
		--platform ${PLATFORMS} \
		--build-arg VERSION=${VERSION} \
		-t ${ECR_REPO}:${VERSION} \
		-t ${ECR_REPO}:latest \
		--load \
		.
	@echo "Built multi-arch image: ${ECR_REPO}:${VERSION}"
	@echo "Platforms: ${PLATFORMS}"

.PHONY: docker-build-multiarch-ecr
docker-build-multiarch-ecr: buildx-setup ecr-login ## Build and tag multi-arch image for ECR (no push)
	docker buildx build \
		--platform ${PLATFORMS} \
		--build-arg VERSION=${VERSION} \
		-t ${DOCKER_IMAGE}:${VERSION} \
		-t ${DOCKER_IMAGE}:latest \
		.
	@echo "Built multi-arch image for ECR: ${DOCKER_IMAGE}:${VERSION}"
	@echo "Platforms: ${PLATFORMS}"
	@echo "Note: Image not pushed. Use 'make docker-push-multiarch' to push."

.PHONY: docker-push-multiarch
docker-push-multiarch: buildx-setup ecr-login ## Build and push multi-arch Docker image to ECR
	docker buildx build \
		--platform ${PLATFORMS} \
		--build-arg VERSION=${VERSION} \
		-t ${DOCKER_IMAGE}:${VERSION} \
		-t ${DOCKER_IMAGE}:latest \
		--push \
		.
	@echo "Pushed multi-arch images to ECR:"
	@echo "  ${DOCKER_IMAGE}:${VERSION}"
	@echo "  ${DOCKER_IMAGE}:latest"
	@echo "Platforms: ${PLATFORMS}"

.PHONY: docker-run
docker-run: ## Run Docker container locally
	docker run -it --rm \
		-p 8025:8025 \
		-p 1025:1025 \
		${ECR_REPO}:latest

# Docker Compose targets
.PHONY: up
up: ## Start mailpit with docker-compose
	docker compose up -d
	@echo "Mailpit started!"
	@echo "Web UI: http://localhost:8025"
	@echo "SMTP: localhost:1025"
	@echo "POP3: localhost:1110"

.PHONY: down
down: ## Stop mailpit
	docker compose down

.PHONY: logs
logs: ## Show mailpit logs
	docker compose logs -f mailpit

.PHONY: restart
restart: ## Restart mailpit
	docker compose restart mailpit

.PHONY: ps
ps: ## Show running containers
	docker compose ps

.PHONY: clean-compose
clean-compose: ## Stop and remove all containers, networks, and volumes
	docker compose down -v
	@echo "Cleaned up all docker-compose resources"

.PHONY: ecr-login
ecr-login: ## Login to AWS ECR
	aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${DOCKER_REGISTRY}
	@echo "Logged in to ECR: ${DOCKER_REGISTRY}"

.PHONY: docker-push
docker-push: ecr-login docker-build-tag ## Build, tag and push Docker image to ECR
	docker push ${DOCKER_IMAGE}:${VERSION}
	docker push ${DOCKER_IMAGE}:latest
	@echo "Pushed images:"
	@echo "  ${DOCKER_IMAGE}:${VERSION}"
	@echo "  ${DOCKER_IMAGE}:latest"

.PHONY: docker-pull
docker-pull: ecr-login ## Pull Docker image from ECR
	docker pull ${DOCKER_IMAGE}:latest
	@echo "Pulled image: ${DOCKER_IMAGE}:latest"

# Deployment helpers
.PHONY: deploy
deploy: docker-push ## Build and deploy to ECR (alias for docker-push)

.PHONY: deploy-multiarch
deploy-multiarch: docker-push-multiarch ## Build and deploy multi-arch images to ECR

.PHONY: version
version: ## Show current version
	@echo "Version: ${VERSION}"
	@echo "Commit:  ${LAST_COMMIT}"
	@echo "Build:   ${BUILDSTR}"

.PHONY: docker-info
docker-info: ## Show Docker image information
	@echo "ECR Repository: ${DOCKER_IMAGE}"
	@echo "Version Tag:    ${VERSION}"
	@echo "Latest Tag:     latest"
	@echo "Platforms:      ${PLATFORMS}"
	@echo "Builder Name:   ${BUILDER_NAME}"
