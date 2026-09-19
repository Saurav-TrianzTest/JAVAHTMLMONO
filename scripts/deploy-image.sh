#!/bin/bash
# =============================================================================
# deploy-image.sh — Deploy acme-portal-static to GCP GKE
# Usage : ./scripts/deploy-image.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

APP_NAME="acme-portal-static"
NAMESPACE="acme-portal-static"

echo "=============================================="
echo "  Deploy to GCP GKE — ${APP_NAME}"
echo "=============================================="

# ── Prompt for GCP / GKE details ─────────────────────────────────────────────
read -rp "Enter GCP Project ID: " GCP_PROJECT
if [ -z "${GCP_PROJECT}" ]; then
  echo "ERROR: GCP Project ID is required." >&2
  exit 1
fi

read -rp "Enter GCP Zone (e.g. us-central1-a) [us-central1-a]: " GCP_ZONE
GCP_ZONE="${GCP_ZONE:-us-central1-a}"

read -rp "Enter GKE Cluster Name: " CLUSTER_NAME
if [ -z "${CLUSTER_NAME}" ]; then
  echo "ERROR: GKE Cluster Name is required." >&2
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. us-central1-docker.pkg.dev/my-project/repo/acme-portal-static:latest): " IMAGE_URI
if [ -z "${IMAGE_URI}" ]; then
  echo "ERROR: Docker image URI is required." >&2
  exit 1
fi

# ── Optional environment variable overrides ───────────────────────────────────
echo ""
echo "--- Optional Environment Variable Overrides ---"
echo "(Press Enter to keep placeholder values in manifests)"

read -rp "Enter API_URL value (or press Enter to skip): " API_URL_VAL

# ── Configure kubectl ─────────────────────────────────────────────────────────
echo ""
echo "Configuring kubectl for cluster: ${CLUSTER_NAME}..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --zone "${GCP_ZONE}" \
  --project "${GCP_PROJECT}"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to cluster." >&2; exit 1; }

# ── Update manifests with actual values ──────────────────────────────────────
echo ""
echo "Updating Kubernetes manifests..."

# Work on copies to avoid modifying originals
cp -r kubernetes/ /tmp/k8s-deploy-${APP_NAME}/

sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" /tmp/k8s-deploy-${APP_NAME}/deployment.yaml

if [ -n "${API_URL_VAL}" ]; then
  sed -i "s|{{API_URL}}|${API_URL_VAL}|g" /tmp/k8s-deploy-${APP_NAME}/deployment.yaml
else
  sed -i "s|{{API_URL}}||g" /tmp/k8s-deploy-${APP_NAME}/deployment.yaml
fi

# ── Apply Kubernetes manifests ────────────────────────────────────────────────
echo ""
echo "Applying Kubernetes manifests..."

echo "  [1/4] Applying namespace..."
kubectl apply -f /tmp/k8s-deploy-${APP_NAME}/namespace.yaml

echo "  [2/4] Applying deployment..."
kubectl apply -f /tmp/k8s-deploy-${APP_NAME}/deployment.yaml

echo "  [3/4] Applying service..."
kubectl apply -f /tmp/k8s-deploy-${APP_NAME}/service.yaml

echo "  [4/4] Applying ingress..."
kubectl apply -f /tmp/k8s-deploy-${APP_NAME}/ingress.yaml

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s

# ── Verify resources ──────────────────────────────────────────────────────────
echo ""
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n ${NAMESPACE}

# ── Display access URL ────────────────────────────────────────────────────────
echo ""
INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "=============================================="
echo "  Deployment complete!"
echo "  Application: ${APP_NAME}"
echo "  Namespace  : ${NAMESPACE}"
echo "  Ingress IP : ${INGRESS_IP}"
if [ "${INGRESS_IP}" != "pending" ] && [ -n "${INGRESS_IP}" ]; then
  echo "  URL        : http://${INGRESS_IP}/"
  echo "  Health     : http://${INGRESS_IP}/api/health"
else
  echo "  (Ingress IP is still provisioning — check again with:)"
  echo "  kubectl get ingress -n ${NAMESPACE}"
fi
echo "=============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"

# ── Cleanup temp files ────────────────────────────────────────────────────────
rm -rf /tmp/k8s-deploy-${APP_NAME}/
