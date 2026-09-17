#!/bin/bash
# =============================================================================
# deploy-image.sh — Deploy acme-portal-static to AWS EKS
# Usage: bash scripts/deploy-image.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

APP_NAME="acme-portal-static"
NAMESPACE="acme-portal-static"

echo "=============================================="
echo "  Deploy: $APP_NAME → AWS EKS"
echo "=============================================="

# ── Prompt for AWS / EKS details ─────────────────────────────────────────────
read -rp "Enter AWS region [us-east-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-us-east-1}"

read -rp "Enter EKS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: EKS cluster name is required." >&2
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Docker image URI is required." >&2
  exit 1
fi

# ── Configure kubectl ─────────────────────────────────────────────────────────
echo ""
echo "Configuring kubectl for cluster: $CLUSTER_NAME ..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to cluster." >&2; exit 1; }

# ── Patch manifests ───────────────────────────────────────────────────────────
echo ""
echo "Updating Kubernetes manifests with image URI..."
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" kubernetes/deployment.yaml

# ── Apply manifests ───────────────────────────────────────────────────────────
echo ""
echo "Applying Kubernetes manifests..."
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "Deployment resources:"
kubectl get pods,svc,ingress -n "$NAMESPACE"

# ── Display URL ───────────────────────────────────────────────────────────────
echo ""
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<pending>")
echo "=============================================="
echo "  Deployment complete!"
echo "  Application URL: http://$INGRESS_HOST"
echo "  Health endpoint: http://$INGRESS_HOST/api/health"
echo "=============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
