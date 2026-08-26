#!/bin/bash
# =============================================================================
# deploy-image.sh – Deploy acme-portal-static to AWS EKS
# =============================================================================
set -e
set -o pipefail

APP_NAME="acme-portal-static"
NAMESPACE="acme-portal-static"

echo "=============================================="
echo "  Deploy to AWS EKS: ${APP_NAME}"
echo "=============================================="

# Prompt for required inputs
read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
if [ -z "${AWS_REGION}" ]; then
  echo "ERROR: AWS Region is required."
  exit 1
fi

read -rp "Enter EKS Cluster Name: " CLUSTER_NAME
if [ -z "${CLUSTER_NAME}" ]; then
  echo "ERROR: EKS Cluster Name is required."
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): " IMAGE_URI
if [ -z "${IMAGE_URI}" ]; then
  echo "ERROR: Docker image URI is required."
  exit 1
fi

# Optional environment variable overrides
echo ""
echo "--- Optional Environment Variable Configuration ---"
read -rp "Enter API_URL (or press Enter to skip): " API_URL_INPUT
if [ -z "${API_URL_INPUT}" ]; then
  API_URL_INPUT="http://localhost:8080"
fi

echo ""
echo "Configuring kubectl for EKS cluster: ${CLUSTER_NAME} in ${AWS_REGION}..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to EKS cluster."; exit 1; }

# Update Kubernetes manifests with actual values (pipe delimiter to handle URLs)
echo ""
echo "Updating Kubernetes manifests with deployment values..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../kubernetes"

sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"   "${K8S_DIR}/deployment.yaml"
sed -i "s|{{API_URL}}|${API_URL_INPUT}|g" "${K8S_DIR}/deployment.yaml"

# Apply manifests in order
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

# Wait for rollout
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=300s

# Verify resources
echo ""
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n "${NAMESPACE}"

# Display application URL
echo ""
echo "Fetching application ingress URL..."
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "${NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo "=============================================="
echo "  Deployment complete!"
echo "  Application URL: http://${INGRESS_HOST}"
echo "  Health endpoint: http://${INGRESS_HOST}/api/health"
echo "=============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
