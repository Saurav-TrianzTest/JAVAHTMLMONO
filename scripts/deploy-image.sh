#!/bin/bash
# =============================================================
# deploy-image.sh — Deploy csat to AWS EKS
# Usage: bash scripts/deploy-image.sh  (from repo root)
# =============================================================
set -e
set -o pipefail

APP_NAME="csat"
NAMESPACE="csat"
K8S_DIR="kubernetes"

echo "============================================="
echo "  Deploy $APP_NAME to AWS EKS"
echo "============================================="

# ── Collect deployment inputs ────────────────────────────────
read -rp "Enter AWS region (e.g. us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
  echo "ERROR: AWS region is required."
  exit 1
fi

read -rp "Enter EKS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: EKS cluster name is required."
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/csat:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Docker image URI is required."
  exit 1
fi

# ── Optional environment variable prompts ────────────────────
echo ""
echo "Optional: Configure application environment variables."
echo "(Press Enter to skip any variable)"

read -rp "Enter value for API_URL (e.g. https://api.example.com): " API_URL_VAL

# ── Update Kubernetes manifests ──────────────────────────────
echo ""
echo "Updating Kubernetes manifests..."

# Use pipe delimiter to avoid conflicts with URI slashes
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "${K8S_DIR}/deployment.yaml"

if [ -n "$API_URL_VAL" ]; then
  sed -i "s|{{API_URL}}|${API_URL_VAL}|g" "${K8S_DIR}/deployment.yaml"
else
  sed -i "s|{{API_URL}}|http://localhost:8080|g" "${K8S_DIR}/deployment.yaml"
fi

echo "Manifests updated."

# ── Configure kubectl for EKS ────────────────────────────────
echo ""
echo "Configuring kubectl for EKS cluster: $CLUSTER_NAME in $AWS_REGION..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to cluster."; exit 1; }

# ── Apply manifests in order ─────────────────────────────────
echo ""
echo "Applying Kubernetes manifests..."

echo "  [1/4] Applying namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "  [2/4] Applying deployment..."
kubectl apply -f "${K8S_DIR}/deployment.yaml"

echo "  [3/4] Applying service..."
kubectl apply -f "${K8S_DIR}/service.yaml"

echo "  [4/4] Applying ingress..."
kubectl apply -f "${K8S_DIR}/ingress.yaml"

# ── Wait for rollout ─────────────────────────────────────────
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=300s

# ── Verify resources ─────────────────────────────────────────
echo ""
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n "${NAMESPACE}"

# ── Display access URL ───────────────────────────────────────
echo ""
echo "Fetching application URL..."
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "${NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo "============================================="
echo "  DEPLOYMENT COMPLETE"
echo "  Application: $APP_NAME"
echo "  Namespace  : $NAMESPACE"
echo "  Image      : $IMAGE_URI"
if [ "$INGRESS_HOST" != "pending" ] && [ -n "$INGRESS_HOST" ]; then
  echo "  URL        : http://$INGRESS_HOST"
else
  echo "  URL        : (ingress hostname pending — check 'kubectl get ingress -n $NAMESPACE')"
fi
echo "============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
