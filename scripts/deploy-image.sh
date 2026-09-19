#!/usr/bin/env bash
# =============================================================================
# deploy-image.sh — Deploy acme-portal-static to AWS ECS Fargate
# Usage: ./scripts/deploy-image.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

SERVICE_NAME="acme-portal-static-service"
TASK_FAMILY="acme-portal-static-task"
LOG_GROUP="/ecs/acme-portal-static"
TASK_DEF_FILE="ecs/task-definition.json"
SERVICE_DEF_FILE="ecs/service-definition.json"

echo "============================================================"
echo "  acme-portal-static — AWS ECS Fargate Deployment"
echo "============================================================"
echo ""

# ── Gather inputs ─────────────────────────────────────────────────────────────
read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
read -rp "Enter ECS Cluster name [acme-portal-static-cluster]: " CLUSTER_INPUT
CLUSTER_NAME="${CLUSTER_INPUT:-acme-portal-static-cluster}"
read -rp "Enter ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): " IMAGE_URI
read -rp "Enter Subnet ID 1 (e.g. subnet-xxxxxxxx): " SUBNET_1
read -rp "Enter Subnet ID 2 (e.g. subnet-yyyyyyyy): " SUBNET_2
read -rp "Enter Security Group ID (e.g. sg-xxxxxxxx): " SECURITY_GROUP

# ── Derive Account ID ─────────────────────────────────────────────────────────
echo ""
echo "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# ── Ensure CloudWatch log group exists ────────────────────────────────────────
echo ""
echo "Ensuring CloudWatch log group '${LOG_GROUP}' exists..."
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${AWS_REGION}" 2>/dev/null || true

# ── Ensure ECS cluster exists ─────────────────────────────────────────────────
echo "Checking ECS cluster '${CLUSTER_NAME}'..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "clusters[0].status" --output text 2>/dev/null || echo "MISSING")
if [ "${CLUSTER_STATUS}" != "ACTIVE" ]; then
  echo "Creating ECS cluster '${CLUSTER_NAME}'..."
  aws ecs create-cluster --cluster-name "${CLUSTER_NAME}" --region "${AWS_REGION}"
fi

# ── Load Balancer ─────────────────────────────────────────────────────────────
echo ""
read -rp "Do you need an Application Load Balancer for this service? (y/n): " NEED_ALB

if [ "${NEED_ALB}" = "y" ] || [ "${NEED_ALB}" = "Y" ]; then
  read -rp "Enter VPC ID for the load balancer (e.g. vpc-xxxxxxxx): " VPC_ID
  read -rp "Enter a name for the ALB [acme-portal-static-alb]: " ALB_NAME_INPUT
  ALB_NAME="${ALB_NAME_INPUT:-acme-portal-static-alb}"
  read -rp "Enter a name for the Target Group [acme-portal-static-tg]: " TG_NAME_INPUT
  TG_NAME="${TG_NAME_INPUT:-acme-portal-static-tg}"

  echo ""
  echo "Creating Application Load Balancer '${ALB_NAME}'..."
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "${ALB_NAME}" \
    --subnets "${SUBNET_1}" "${SUBNET_2}" \
    --security-groups "${SECURITY_GROUP}" \
    --scheme internet-facing \
    --type application \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)
  echo "ALB ARN: ${ALB_ARN}"

  echo "Creating Target Group '${TG_NAME}' (target-type: ip for Fargate awsvpc)..."
  TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name "${TG_NAME}" \
    --protocol HTTP \
    --port 8080 \
    --vpc-id "${VPC_ID}" \
    --target-type ip \
    --health-check-path "/api/health" \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region "${AWS_REGION}" \
    --query "TargetGroups[0].TargetGroupArn" --output text)
  echo "Target Group ARN: ${TARGET_GROUP_ARN}"

  echo "Creating ALB Listener on port 80..."
  aws elbv2 create-listener \
    --load-balancer-arn "${ALB_ARN}" \
    --protocol HTTP \
    --port 80 \
    --default-actions "Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}" \
    --region "${AWS_REGION}" >/dev/null

  ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "${ALB_ARN}" \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[0].DNSName" --output text)

  # Inject load balancer config into service definition
  python3 - <<PYEOF
import json, sys
with open("${SERVICE_DEF_FILE}") as f:
    svc = json.load(f)
svc["loadBalancers"] = [{
    "targetGroupArn": "${TARGET_GROUP_ARN}",
    "containerName": "acme-portal-static",
    "containerPort": 8080
}]
svc["healthCheckGracePeriodSeconds"] = 300
with open("${SERVICE_DEF_FILE}", "w") as f:
    json.dump(svc, f, indent=2)
PYEOF
  USE_ALB=true
else
  # Remove loadBalancers key if present
  python3 - <<PYEOF
import json
with open("${SERVICE_DEF_FILE}") as f:
    svc = json.load(f)
svc.pop("loadBalancers", None)
svc.pop("healthCheckGracePeriodSeconds", None)
with open("${SERVICE_DEF_FILE}", "w") as f:
    json.dump(svc, f, indent=2)
PYEOF
  USE_ALB=false
fi

# ── Substitute placeholders in task definition ────────────────────────────────
echo ""
echo "Preparing task definition..."
cp "${TASK_DEF_FILE}" /tmp/task-definition-deploy.json
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"       /tmp/task-definition-deploy.json
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g"     /tmp/task-definition-deploy.json
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g"     /tmp/task-definition-deploy.json

# ── Substitute placeholders in service definition ─────────────────────────────
cp "${SERVICE_DEF_FILE}" /tmp/service-definition-deploy.json
sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g"   /tmp/service-definition-deploy.json
sed -i "s|{{SUBNET_1}}|${SUBNET_1}|g"           /tmp/service-definition-deploy.json
sed -i "s|{{SUBNET_2}}|${SUBNET_2}|g"           /tmp/service-definition-deploy.json
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" /tmp/service-definition-deploy.json

# ── Register task definition ──────────────────────────────────────────────────
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-definition-deploy.json \
  --region "${AWS_REGION}" \
  --query "taskDefinition.taskDefinitionArn" --output text)
echo "Task Definition ARN: ${TASK_DEF_ARN}"

# ── Create or update ECS service ──────────────────────────────────────────────
echo ""
EXISTING_SERVICE=$(aws ecs describe-services \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}" \
  --query "services[?status=='ACTIVE'].serviceName" \
  --output text 2>/dev/null || echo "")

if [ -z "${EXISTING_SERVICE}" ] || [ "${EXISTING_SERVICE}" = "None" ]; then
  echo "Creating ECS service '${SERVICE_NAME}'..."
  # Inject resolved task definition ARN
  python3 - <<PYEOF
import json
with open("/tmp/service-definition-deploy.json") as f:
    svc = json.load(f)
svc["taskDefinition"] = "${TASK_DEF_ARN}"
with open("/tmp/service-definition-deploy.json", "w") as f:
    json.dump(svc, f, indent=2)
PYEOF
  aws ecs create-service \
    --cli-input-json file:///tmp/service-definition-deploy.json \
    --region "${AWS_REGION}"
else
  echo "Updating existing ECS service '${SERVICE_NAME}'..."
  aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --task-definition "${TASK_DEF_ARN}" \
    --region "${AWS_REGION}"
fi

# ── Wait for stability ────────────────────────────────────────────────────────
echo ""
echo "Waiting for service to stabilize (this may take a few minutes)..."
aws ecs wait services-stable \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}"

# ── Verify deployment ─────────────────────────────────────────────────────────
echo ""
echo "Deployment complete. Service status:"
aws ecs describe-services \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}" \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDef:taskDefinition}" \
  --output table

echo ""
echo "============================================================"
echo "  Deployment Summary"
echo "============================================================"
echo "  Cluster      : ${CLUSTER_NAME}"
echo "  Service      : ${SERVICE_NAME}"
echo "  Task Def ARN : ${TASK_DEF_ARN}"
echo "  CloudWatch   : ${LOG_GROUP}"
if [ "${USE_ALB}" = "true" ]; then
  echo "  ALB DNS      : http://${ALB_DNS}"
fi
echo "============================================================"
echo ""
echo "Troubleshooting tips:"
echo "  View logs  : aws logs tail ${LOG_GROUP} --follow --region ${AWS_REGION}"
echo "  List tasks : aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --region ${AWS_REGION}"
echo "  Stop tasks : aws ecs stop-task --cluster ${CLUSTER_NAME} --task <TASK_ARN> --region ${AWS_REGION}"
