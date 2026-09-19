#!/bin/bash
# =============================================================
# build-push.sh — Build and push the csat Docker image
# Supports: AWS ECR and Docker Hub
# Usage   : bash scripts/build-push.sh  (from repo root)
# =============================================================
set -e
set -o pipefail

PROJECT_NAME="csat"
DOCKERFILE_PATH="Dockerfile"

# ── Sanitize image name ──────────────────────────────────────
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "============================================="
echo "  Build & Push: $IMAGE_NAME"
echo "============================================="

# ── Registry selection ───────────────────────────────────────
echo ""
echo "Select container registry:"
echo "  1) AWS ECR"
echo "  2) Docker Hub"
read -rp "Enter choice [1-2]: " REGISTRY_CHOICE

# ── Image tag ────────────────────────────────────────────────
read -rp "Enter image tag (default: latest): " RAW_TAG
IMAGE_TAG=$(echo "${RAW_TAG:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG="${IMAGE_TAG:-latest}"
echo "Using tag: $IMAGE_TAG"

# ── Registry-specific logic ──────────────────────────────────
if [ "$REGISTRY_CHOICE" = "1" ]; then
  # ── AWS ECR ─────────────────────────────────────────────────
  read -rp "Enter AWS region (e.g. us-east-1): " AWS_REGION
  read -rp "Enter AWS account ID: " AWS_ACCOUNT_ID
  ECR_REPO="$IMAGE_NAME"
  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to AWS ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY_URL"

  echo "Ensuring ECR repository exists..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"

elif [ "$REGISTRY_CHOICE" = "2" ]; then
  # ── Docker Hub ───────────────────────────────────────────────
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo "Logging in to Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin

else
  echo "Invalid choice. Exiting."
  exit 1
fi

# ── Build ────────────────────────────────────────────────────
echo ""
echo "Building Docker image: $FULL_IMAGE_NAME"
docker build -f "$DOCKERFILE_PATH" -t "$FULL_IMAGE_NAME" .

# ── Push ─────────────────────────────────────────────────────
echo ""
echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

echo ""
echo "============================================="
echo "  SUCCESS: $FULL_IMAGE_NAME"
echo "============================================="
