# Try to get the commit hash from 1) git 2) fallback.
LAST_COMMIT := $(or $(shell git rev-parse --short HEAD 2> /dev/null),"dev")

# Try to get the semver from 1) git 2) fallback.
VERSION := $(or $(MAILPIT_VERSION),$(shell git describe --tags --abbrev=0 2> /dev/null),"v0.0.0")

BUILDSTR := ${VERSION} (\#${LAST_COMMIT} $(shell date -u +"%Y-%m-%dT%H:%M:%S%z"))

# Docker configuration
DOCKER_REGISTRY ?= 963975194089.dkr.ecr.ap-southeast-1.amazonaws.com
ECR_REPO := techinasia-tools/mailpit
DOCKER_IMAGE := ${DOCKER_REGISTRY}/${ECR_REPO}

# Default AWS region
AWS_REGION ?= ap-southeast-1

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

.PHONY: docker-run
docker-run: ## Run Docker container locally
	docker run -it --rm \
		-p 8025:8025 \
		-p 1025:1025 \
		${ECR_REPO}:latest

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
