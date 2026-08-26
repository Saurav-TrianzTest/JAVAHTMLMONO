#!/bin/bash
# =============================================================================
# build-push.sh – Build and push Docker image for acme-portal-static
# Target: AWS ECR or Docker Hub
# =============================================================================
set -e
set -o pipefail

PROJECT_NAME="acme-portal-static"

echo "=============================================="
echo "  Build & Push: ${PROJECT_NAME}"
echo "=============================================="

# Sanitize image name: lowercase, replace non-alphanumeric with hyphens, trim hyphens
IMAGE_NAME=$(echo "${PROJECT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# Prompt for image tag
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "${IMAGE_TAG}" ]; then
  IMAGE_TAG="latest"
fi

echo ""
echo "Select container registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -rp "Enter choice [1 or 2]: " REGISTRY_CHOICE

if [ "${REGISTRY_CHOICE}" = "1" ]; then
  # ---- AWS ECR ----
  read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
  read -rp "Enter AWS Account ID: " AWS_ACCOUNT_ID

  ECR_REPO="${IMAGE_NAME}"
  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to AWS ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${REGISTRY_URL}"

  echo "Ensuring ECR repository exists..."
  aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}"

elif [ "${REGISTRY_CHOICE}" = "2" ]; then
  # ---- Docker Hub ----
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  read -rp "Enter Docker Hub repository (e.g. myorg/${IMAGE_NAME}): " DOCKER_REPO

  FULL_IMAGE_NAME="${DOCKER_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to Docker Hub..."
  echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin

else
  echo "Invalid choice. Exiting."
  exit 1
fi

echo ""
echo "Building Docker image: ${FULL_IMAGE_NAME}"
docker build -f Dockerfile -t "${FULL_IMAGE_NAME}" .

echo ""
echo "Pushing Docker image: ${FULL_IMAGE_NAME}"
docker push "${FULL_IMAGE_NAME}"

echo ""
echo "=============================================="
echo "  Successfully pushed: ${FULL_IMAGE_NAME}"
echo "=============================================="
