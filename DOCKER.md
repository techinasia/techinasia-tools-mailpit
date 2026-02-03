# Docker Deployment Guide

This guide covers both local development with Docker Compose and production deployment to AWS ECR.

## Local Development with Docker Compose

### Quick Start

1. Start mailpit:
   ```bash
   make up
   ```

2. Access the services:
   - **Web UI**: http://localhost:8025
   - **SMTP**: localhost:1025
   - **POP3**: localhost:1110 (optional)

3. Stop mailpit:
   ```bash
   make down
   ```

### Available Commands

| Command | Description |
|---------|-------------|
| `make up` | Start mailpit in detached mode |
| `make down` | Stop mailpit |
| `make logs` | Follow mailpit logs |
| `make restart` | Restart mailpit |
| `make ps` | Show running containers |
| `make clean-compose` | Stop and remove all resources including volumes |

### Configuration

You can customize the configuration by creating a `.env` file:

```bash
cp .env.example .env
# Edit .env with your preferred settings
```

Available environment variables:
- `VERSION`: Version to build (default: `dev`)
- `WEB_PORT`: Web UI port (default: `8025`)
- `SMTP_PORT`: SMTP server port (default: `1025`)
- `POP3_PORT`: POP3 server port (default: `1110`)
- `MP_MAX_MESSAGES`: Maximum messages to store (default: `500`)

### Data Persistence

Email data is stored in a Docker volume named `mailpit-data`. This persists between container restarts.

To completely reset mailpit and remove all emails:
```bash
make clean-compose
```

## Production Deployment to AWS ECR

### Prerequisites

1. Configure AWS credentials with ECR access
2. Create `config.mk` from the sample:
   ```bash
   make config
   ```
3. Edit `config.mk` and update `AWS_ACCOUNT_ID` with your AWS account ID

### Deployment Commands

| Command | Description |
|---------|-------------|
| `make docker-build` | Build Docker image locally |
| `make docker-build-tag` | Build and tag for ECR |
| `make docker-push` | Build, tag, and push to ECR |
| `make deploy` | Complete deployment (alias for docker-push) |
| `make ecr-login` | Login to AWS ECR |
| `make docker-pull` | Pull image from ECR |

### Multi-Architecture Deployment Commands

| Command | Description |
|---------|-------------|
| `make buildx-setup` | Setup buildx builder for multi-arch builds |
| `make docker-build-multiarch` | Build multi-arch image locally |
| `make docker-push-multiarch` | Build and push multi-arch to ECR |
| `make deploy-multiarch` | Complete multi-arch deployment |
| `make buildx-remove` | Remove buildx builder |

### Deploy to ECR

One-command deployment:
```bash
make deploy
```

This will:
1. Login to AWS ECR
2. Build the Docker image
3. Tag with version and latest
4. Push to ECR repository: `techinasia-tools/mailpit`

### Deploy Multi-Architecture Images to ECR

For production deployments supporting both AMD64 and ARM64 architectures:

```bash
make deploy-multiarch
```

This will:
1. Setup Docker buildx builder (if needed)
2. Login to AWS ECR
3. Build Docker images for `linux/amd64` and `linux/arm64`
4. Push multi-arch manifest to ECR

**Supported Platforms:**
- `linux/amd64` (Intel/AMD processors)
- `linux/arm64` (ARM processors, including AWS Graviton)

**Custom platforms:**
```bash
# Build for specific platforms
PLATFORMS=linux/amd64,linux/arm64,linux/arm/v7 make deploy-multiarch
```

**First-time setup:**
```bash
# Setup buildx builder
make buildx-setup

# Verify builder
docker buildx ls
```

### Configuration

Edit `config.mk` to customize:
```makefile
AWS_ACCOUNT_ID := your-aws-account-id
AWS_REGION := ap-southeast-1
```

### Version Management

The Makefile automatically:
- Detects version from git tags
- Uses commit hash for build tracking
- Tags images with both version and `latest`

Check current version:
```bash
make version
```

## Docker Run (Without Compose)

Build and run locally without docker-compose:
```bash
make docker-build
make docker-run
```

## Healthcheck

The Docker image includes a built-in healthcheck:
```bash
docker inspect --format='{{.State.Health.Status}}' mailpit
```

## Troubleshooting

### View logs
```bash
make logs
```

### Check container status
```bash
make ps
```

### Rebuild from scratch
```bash
make down
docker compose build --no-cache
make up
```

### Reset everything
```bash
make clean-compose
```

## Advanced Configuration

For advanced configuration options (authentication, TLS, etc.), edit the `docker-compose.yml` file directly and uncomment the relevant sections.

Refer to the [official Mailpit documentation](https://mailpit.axllent.org/docs/) for all available configuration options.
