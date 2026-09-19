#!/bin/bash
# =============================================================================
# build-push.sh — Build and push Docker image for acme-portal-static
# Target: GCP GKE
# Usage : ./scripts/build-push.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

PROJECT_NAME="acme-portal-static"

echo "=============================================="
echo "  Build & Push — ${PROJECT_NAME}"
echo "=============================================="

# ── Sanitize image name ───────────────────────────────────────────────────────
IMAGE_NAME=$(echo "${PROJECT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# ── Prompt for image tag ──────────────────────────────────────────────────────
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG="${IMAGE_TAG:-latest}"
echo "Using image tag: ${IMAGE_TAG}"

# ── Registry selection ────────────────────────────────────────────────────────
echo ""
echo "Select container registry:"
echo "  1) Google Artifact Registry"
echo "  2) Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "${REGISTRY_CHOICE}" = "1" ]; then
  # ── Google Artifact Registry ────────────────────────────────────────────────
  echo ""
  echo "--- Google Artifact Registry ---"
  read -rp "Enter GCP Project ID: " GCP_PROJECT
  if [ -z "${GCP_PROJECT}" ]; then
    echo "ERROR: GCP Project ID is required." >&2
    exit 1
  fi

  read -rp "Enter GCP Region (e.g. us-central1) [us-central1]: " GCP_REGION
  GCP_REGION="${GCP_REGION:-us-central1}"

  read -rp "Enter Artifact Registry repository name [${IMAGE_NAME}]: " AR_REPO
  AR_REPO="${AR_REPO:-${IMAGE_NAME}}"

  FULL_IMAGE_NAME="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Authenticating with Google Artifact Registry..."
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

elif [ "${REGISTRY_CHOICE}" = "2" ]; then
  # ── Docker Hub ──────────────────────────────────────────────────────────────
  echo ""
  echo "--- Docker Hub ---"
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  if [ -z "${DOCKER_USERNAME}" ]; then
    echo "ERROR: Docker Hub username is required." >&2
    exit 1
  fi

  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  if [ -z "${DOCKER_PASSWORD}" ]; then
    echo "ERROR: Docker Hub password/token is required." >&2
    exit 1
  fi

  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Authenticating with Docker Hub..."
  echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin

else
  echo "ERROR: Invalid registry choice '${REGISTRY_CHOICE}'." >&2
  exit 1
fi

echo ""
echo "Building Docker image: ${FULL_IMAGE_NAME}"
echo "Build context: . (repository root)"
docker build -f Dockerfile -t "${FULL_IMAGE_NAME}" .
echo "Docker build succeeded."

echo ""
echo "Pushing image: ${FULL_IMAGE_NAME}"
docker push "${FULL_IMAGE_NAME}"
echo "Docker push succeeded."

echo ""
echo "=============================================="
echo "  Image pushed successfully!"
echo "  ${FULL_IMAGE_NAME}"
echo "=============================================="
