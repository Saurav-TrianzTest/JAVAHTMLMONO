#!/bin/bash
# =============================================================================
# build-push.sh – acme-portal-static (JAVAHTMLMONO)
# Build Docker image and push to AWS ECR or Docker Hub
# Usage: ./scripts/build-push.sh
# Run from repository root directory
# =============================================================================

set -e
set -o pipefail

PROJECT_NAME="acme-portal-static"
DOCKERFILE_PATH="Dockerfile"
BUILD_CONTEXT="."

echo "=============================================="
echo "  acme-portal-static – Build & Push Script"
echo "=============================================="
echo ""

# ── Tag sanitisation ──────────────────────────────────────────────────────────
# Sanitise project name: lowercase, replace non-alphanumeric with hyphens,
# trim leading/trailing hyphens
IMAGE_NAME=$(echo "${PROJECT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "Project name  : ${PROJECT_NAME}"
echo "Image name    : ${IMAGE_NAME}"
echo ""

# ── Prompt for image tag ──────────────────────────────────────────────────────
read -rp "Enter image tag [latest]: " RAW_TAG
RAW_TAG="${RAW_TAG:-latest}"
IMAGE_TAG=$(echo "${RAW_TAG}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "${IMAGE_TAG}" ]; then
  IMAGE_TAG="latest"
fi
echo "Image tag     : ${IMAGE_TAG}"
echo ""

# ── Registry selection ────────────────────────────────────────────────────────
echo "Select container registry:"
echo "  1) AWS ECR"
echo "  2) Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "${REGISTRY_CHOICE}" = "1" ]; then
  # ── AWS ECR ──────────────────────────────────────────────────────────────
  echo ""
  echo "── AWS ECR Configuration ──────────────────────────────────────────────"
  read -rp "AWS Region [us-east-1]: " AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"

  read -rp "AWS Account ID: " AWS_ACCOUNT_ID
  if [ -z "${AWS_ACCOUNT_ID}" ]; then
    echo "Fetching AWS Account ID from STS..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Account ID    : ${AWS_ACCOUNT_ID}"
  fi

  read -rp "ECR Repository name [${IMAGE_NAME}]: " ECR_REPO
  ECR_REPO="${ECR_REPO:-${IMAGE_NAME}}"

  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Registry URL  : ${REGISTRY_URL}"
  echo "Full image    : ${FULL_IMAGE_NAME}"
  echo ""

  # Authenticate to ECR
  echo "Authenticating to AWS ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${REGISTRY_URL}"
  echo "ECR authentication successful."

  # Auto-create ECR repository if it does not exist
  echo "Checking ECR repository '${ECR_REPO}'..."
  aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}"
  echo "ECR repository ready."

elif [ "${REGISTRY_CHOICE}" = "2" ]; then
  # ── Docker Hub ────────────────────────────────────────────────────────────
  echo ""
  echo "── Docker Hub Configuration ───────────────────────────────────────────"
  read -rp "Docker Hub username: " DOCKER_USERNAME
  read -rsp "Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  read -rp "Docker Hub namespace/org [${DOCKER_USERNAME}]: " DOCKER_NAMESPACE
  DOCKER_NAMESPACE="${DOCKER_NAMESPACE:-${DOCKER_USERNAME}}"

  FULL_IMAGE_NAME="${DOCKER_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Full image    : ${FULL_IMAGE_NAME}"
  echo ""

  # Authenticate to Docker Hub
  echo "Authenticating to Docker Hub..."
  echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin
  echo "Docker Hub authentication successful."

else
  echo "ERROR: Invalid registry choice '${REGISTRY_CHOICE}'. Exiting." >&2
  exit 1
fi

# ── Build Docker image ────────────────────────────────────────────────────────
echo ""
echo "Building Docker image..."
echo "  Dockerfile : ${DOCKERFILE_PATH}"
echo "  Context    : ${BUILD_CONTEXT}"
echo "  Tag        : ${FULL_IMAGE_NAME}"
echo ""

docker build \
  -f "${DOCKERFILE_PATH}" \
  -t "${FULL_IMAGE_NAME}" \
  "${BUILD_CONTEXT}"

if [ $? -ne 0 ]; then
  echo "ERROR: Docker build failed." >&2
  exit 1
fi
echo "Docker build successful."

# ── Push Docker image ─────────────────────────────────────────────────────────
echo ""
echo "Pushing image to registry..."
docker push "${FULL_IMAGE_NAME}"

if [ $? -ne 0 ]; then
  echo "ERROR: Docker push failed." >&2
  exit 1
fi

echo ""
echo "=============================================="
echo "  Build & Push Complete!"
echo "  Image: ${FULL_IMAGE_NAME}"
echo "=============================================="
echo ""
echo "Next step: Run scripts/deploy-image.sh to deploy to AWS ECS Fargate."
