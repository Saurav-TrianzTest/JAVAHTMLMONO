#!/bin/bash
# =============================================================
# deploy-image.sh – Deploy acme-portal-static to Azure AKS
#
# Usage: bash scripts/deploy-image.sh
# Run from the repository root directory.
# Prerequisites: azure-cli, kubectl
# =============================================================
set -e
set -o pipefail

APP_NAME="acme-portal-static"
NAMESPACE="acme-portal-static"

echo "=============================================="
echo "  acme-portal-static – Deploy to Azure AKS"
echo "=============================================="
echo ""

# ── Prompt for Azure details ─────────────────────────────────
read -rp "Enter Azure Resource Group name: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
  echo "ERROR: Resource group cannot be empty." >&2
  exit 1
fi

read -rp "Enter AKS Cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: AKS cluster name cannot be empty." >&2
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. myregistry.azurecr.io/acme-portal-static:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Image URI cannot be empty." >&2
  exit 1
fi

# ── Prompt for optional environment variables ─────────────────
echo ""
echo "--- Optional Environment Variables ---"
echo "(Press Enter to skip any variable)"
read -rp "Enter value for API_URL (e.g. https://api.example.com): " API_URL_VAL
API_URL_VAL="${API_URL_VAL:-http://localhost:8080}"

# ── Configure kubectl for AKS ────────────────────────────────
echo ""
echo "Configuring kubectl for AKS cluster: $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to get AKS credentials." >&2
  exit 1
fi

# ── Verify cluster connectivity ──────────────────────────────
echo ""
echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "ERROR: Cannot connect to Kubernetes cluster." >&2; exit 1; }

# ── Prepare manifest copies ──────────────────────────────────
echo ""
echo "Preparing Kubernetes manifests ..."
DEPLOY_DIR="$(mktemp -d)"
cp kubernetes/namespace.yaml  "$DEPLOY_DIR/namespace.yaml"
cp kubernetes/deployment.yaml "$DEPLOY_DIR/deployment.yaml"
cp kubernetes/service.yaml    "$DEPLOY_DIR/service.yaml"
cp kubernetes/ingress.yaml    "$DEPLOY_DIR/ingress.yaml"

# ── Replace placeholders with sed (pipe delimiter) ───────────
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"   "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{API_URL}}|${API_URL_VAL}|g"   "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{NAMESPACE}}|${NAMESPACE}|g"   "$DEPLOY_DIR/deployment.yaml"

# ── Apply manifests in order ─────────────────────────────────
echo ""
echo "Applying Kubernetes manifests ..."

echo "  [1/4] Applying namespace ..."
kubectl apply -f "$DEPLOY_DIR/namespace.yaml"

echo "  [2/4] Applying deployment ..."
kubectl apply -f "$DEPLOY_DIR/deployment.yaml"

echo "  [3/4] Applying service ..."
kubectl apply -f "$DEPLOY_DIR/service.yaml"

echo "  [4/4] Applying ingress ..."
kubectl apply -f "$DEPLOY_DIR/ingress.yaml"

# ── Wait for rollout ─────────────────────────────────────────
echo ""
echo "Waiting for deployment rollout ..."
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s
if [ $? -ne 0 ]; then
  echo ""
  echo "ERROR: Deployment rollout failed. Rolling back ..." >&2
  kubectl rollout undo deployment/"$APP_NAME" -n "$NAMESPACE"
  echo "Rollback initiated. Check pod logs:"
  echo "  kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

# ── Verify resources ─────────────────────────────────────────
echo ""
echo "Verifying deployed resources ..."
kubectl get pods,svc,ingress -n "$NAMESPACE"

# ── Display access URL ───────────────────────────────────────
echo ""
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "acme-portal-static.example.com")
echo "=============================================="
echo "  Deployment complete!"
echo "  Application URL: http://${INGRESS_HOST}"
echo "  Health endpoint: http://${INGRESS_HOST}/api/health"
echo ""
echo "  Useful commands:"
echo "    kubectl get pods -n $NAMESPACE"
echo "    kubectl logs -l app=$APP_NAME -n $NAMESPACE"
echo "    kubectl describe deployment $APP_NAME -n $NAMESPACE"
echo "    kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE  # rollback"
echo "=============================================="

# ── Cleanup temp dir ─────────────────────────────────────────
rm -rf "$DEPLOY_DIR"
