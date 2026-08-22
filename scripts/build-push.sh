#!/bin/bash
# =============================================================================
# build-push.sh – acme-portal-static (JAVAHTMLGIT)
#
# Builds the Docker image and pushes it to either AWS ECR or Docker Hub.
# Run this script from the repository root directory.
#
# Usage:
#   chmod +x scripts/build-push.sh
#   ./scripts/build-push.sh
# =============================================================================

set -e
set -o pipefail

PROJECT_NAME="acme-portal-static"
DOCKERFILE_PATH="Dockerfile"

echo "=============================================="
echo "  acme-portal-static – Build & Push Script"
echo "=============================================="
echo ""

# ── Tag sanitization ──────────────────────────────────────────────────────────
# Lowercase, replace non-alphanumeric with hyphens, trim leading/trailing hyphens
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "Project name  : $PROJECT_NAME"
echo "Image name    : $IMAGE_NAME"
echo ""

# ── Prompt for image tag ──────────────────────────────────────────────────────
read -rp "Enter image tag [latest]: " INPUT_TAG
INPUT_TAG=$(echo "${INPUT_TAG:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG="${INPUT_TAG:-latest}"
echo "Image tag     : $IMAGE_TAG"
echo ""

# ── Registry selection ────────────────────────────────────────────────────────
echo "Select container registry:"
echo "  1. AWS ECR (Elastic Container Registry)"
echo "  2. Docker Hub"
echo ""
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "$REGISTRY_CHOICE" = "1" ]; then
    # ── AWS ECR ───────────────────────────────────────────────────────────────
    echo ""
    echo "--- AWS ECR Configuration ---"
    read -rp "Enter AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION="${AWS_REGION:-us-east-1}"

    read -rp "Enter AWS Account ID: " AWS_ACCOUNT_ID
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        echo "Fetching AWS Account ID from STS..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        echo "AWS Account ID: $AWS_ACCOUNT_ID"
    fi

    read -rp "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO
    ECR_REPO="${ECR_REPO:-$IMAGE_NAME}"

    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

    echo ""
    echo "Registry URL  : $REGISTRY_URL"
    echo "Full image    : $FULL_IMAGE_NAME"
    echo ""

    # Authenticate to ECR
    echo "Authenticating to AWS ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$REGISTRY_URL"
    echo "ECR authentication successful."

    # Auto-create ECR repository if it does not exist
    echo "Checking if ECR repository '$ECR_REPO' exists..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    echo "ECR repository ready."

elif [ "$REGISTRY_CHOICE" = "2" ]; then
    # ── Docker Hub ────────────────────────────────────────────────────────────
    echo ""
    echo "--- Docker Hub Configuration ---"
    read -rp "Enter Docker Hub username: " DOCKER_USERNAME
    read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
    read -rp "Enter Docker Hub namespace [$DOCKER_USERNAME]: " DOCKER_NAMESPACE
    DOCKER_NAMESPACE="${DOCKER_NAMESPACE:-$DOCKER_USERNAME}"

    FULL_IMAGE_NAME="${DOCKER_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "Full image    : $FULL_IMAGE_NAME"
    echo ""

    # Authenticate to Docker Hub
    echo "Authenticating to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    echo "Docker Hub authentication successful."

else
    echo "ERROR: Invalid registry choice '$REGISTRY_CHOICE'. Please enter 1 or 2."
    exit 1
fi

# ── Build Docker image ────────────────────────────────────────────────────────
echo ""
echo "Building Docker image: $FULL_IMAGE_NAME"
echo "Build context: . (repository root)"
echo "Dockerfile   : $DOCKERFILE_PATH"
echo ""

docker build -f "$DOCKERFILE_PATH" -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed."
    exit 1
fi
echo "Docker build successful."

# Also tag as latest if a specific tag was provided
if [ "$IMAGE_TAG" != "latest" ]; then
    if [ "$REGISTRY_CHOICE" = "1" ]; then
        LATEST_IMAGE="${REGISTRY_URL}/${ECR_REPO}:latest"
    else
        LATEST_IMAGE="${DOCKER_NAMESPACE}/${IMAGE_NAME}:latest"
    fi
    docker tag "$FULL_IMAGE_NAME" "$LATEST_IMAGE"
    echo "Tagged as: $LATEST_IMAGE"
fi

# ── Push Docker image ─────────────────────────────────────────────────────────
echo ""
echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed."
    exit 1
fi

if [ "$IMAGE_TAG" != "latest" ]; then
    echo "Pushing image: $LATEST_IMAGE"
    docker push "$LATEST_IMAGE"
fi

echo ""
echo "=============================================="
echo "  Build & Push Complete!"
echo "  Image: $FULL_IMAGE_NAME"
echo "=============================================="
