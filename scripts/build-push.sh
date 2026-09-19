#!/bin/bash
# =============================================================
# build-push.sh – Build and push the acme-portal-static Docker
# image to Azure ACR or Docker Hub.
#
# Usage: bash scripts/build-push.sh
# Run from the repository root directory.
# =============================================================
set -e
set -o pipefail

PROJECT_NAME="acme-portal-static"

echo "=============================================="
echo "  acme-portal-static – Docker Build & Push"
echo "=============================================="
echo ""

# ── Sanitize image name ──────────────────────────────────────
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# ── Prompt for image tag ─────────────────────────────────────
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi
echo "Image tag: $IMAGE_TAG"
echo ""

# ── Registry selection ───────────────────────────────────────
echo "Select container registry:"
echo "  1. Azure Container Registry (ACR)"
echo "  2. Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "$REGISTRY_CHOICE" = "1" ]; then
  # ── Azure ACR ──────────────────────────────────────────────
  echo ""
  echo "--- Azure Container Registry ---"
  read -rp "Enter ACR name (e.g. myregistry): " ACR_NAME
  if [ -z "$ACR_NAME" ]; then
    echo "ERROR: ACR name cannot be empty." >&2
    exit 1
  fi

  ACR_NAME_LOWER=$(echo "$ACR_NAME" | tr '[:upper:]' '[:lower:]')
  FULL_IMAGE_NAME="${ACR_NAME_LOWER}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to ACR: $ACR_NAME_LOWER ..."
  az acr login --name "$ACR_NAME_LOWER"
  if [ $? -ne 0 ]; then
    echo "ERROR: ACR login failed." >&2
    exit 1
  fi

elif [ "$REGISTRY_CHOICE" = "2" ]; then
  # ── Docker Hub ─────────────────────────────────────────────
  echo ""
  echo "--- Docker Hub ---"
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  if [ -z "$DOCKER_USERNAME" ]; then
    echo "ERROR: Docker Hub username cannot be empty." >&2
    exit 1
  fi
  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  if [ -z "$DOCKER_PASSWORD" ]; then
    echo "ERROR: Docker Hub password cannot be empty." >&2
    exit 1
  fi

  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to Docker Hub ..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
  if [ $? -ne 0 ]; then
    echo "ERROR: Docker Hub login failed." >&2
    exit 1
  fi

else
  echo "ERROR: Invalid registry choice '$REGISTRY_CHOICE'. Please enter 1 or 2." >&2
  exit 1
fi

echo ""
echo "Full image name: $FULL_IMAGE_NAME"
echo ""

# ── Build Docker image ───────────────────────────────────────
echo "Building Docker image ..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .
if [ $? -ne 0 ]; then
  echo "ERROR: Docker build failed." >&2
  exit 1
fi
echo "Docker build succeeded."
echo ""

# ── Push Docker image ────────────────────────────────────────
echo "Pushing image to registry ..."
docker push "$FULL_IMAGE_NAME"
if [ $? -ne 0 ]; then
  echo "ERROR: Docker push failed." >&2
  exit 1
fi

echo ""
echo "=============================================="
echo "  Image pushed successfully!"
echo "  $FULL_IMAGE_NAME"
echo "=============================================="
