# Deployment Guide — acme-portal-static on AWS EKS

## Overview

This guide covers building, pushing, and deploying the **acme-portal-static** Java application to **AWS Elastic Kubernetes Service (EKS)**.

- **Application**: acme-portal-static (Java 17, Maven, JDK HTTP server)
- **Runtime image**: `amazoncorretto:17`
- **Health endpoint**: `GET /api/health`
- **Application port**: `8080`
- **Target platform**: AWS EKS

---

## Prerequisites

### Local Tools Required

| Tool | Version | Install |
|------|---------|---------|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| AWS CLI | 2.x | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| kubectl | 1.27+ | https://kubernetes.io/docs/tasks/tools/ |
| eksctl (optional) | 0.150+ | https://eksctl.io/introduction/#installation |

### AWS Permissions Required

Your IAM user/role must have:
- `ecr:GetAuthorizationToken`, `ecr:CreateRepository`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`
- `eks:DescribeCluster`, `eks:UpdateKubeconfig`
- `elasticloadbalancing:*` (for ALB Ingress Controller)

---

## 1. Local Development with Docker Compose

```bash
# Build and start the application locally
docker compose up --build

# Verify health
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}

# Stop
docker compose down
```

---

## 2. Build and Push Docker Image

### Linux / macOS

```bash
bash scripts/build-push.sh
```

The script will prompt for:
1. Image tag (default: `latest`)
2. Registry type: `1` for AWS ECR, `2` for Docker Hub
3. Registry-specific credentials

### Windows

```cmd
scripts\build-push.bat
```

### Manual Build (ECR example)

```bash
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
IMAGE_TAG=1.0.0

# Authenticate
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repo (first time only)
aws ecr create-repository --repository-name acme-portal-static --region $AWS_REGION

# Build & push
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/acme-portal-static:${IMAGE_TAG} .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/acme-portal-static:${IMAGE_TAG}
```

---

## 3. AWS EKS Cluster Setup

### Option A — Use an Existing Cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl cluster-info
```

### Option B — Create a New Cluster with eksctl

```bash
eksctl create cluster \
  --name acme-portal-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

### Install AWS Load Balancer Controller (required for ALB Ingress)

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<your-cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 4. Deploy to AWS EKS

### Linux / macOS

```bash
bash scripts/deploy-image.sh
```

The script will prompt for:
1. AWS region
2. EKS cluster name
3. Full Docker image URI (e.g. `123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest`)

### Windows

```cmd
scripts\deploy-image.bat
```

### Manual Deployment

```bash
# Set image URI in deployment manifest
sed -i 's|{{IMAGE_URI}}|<YOUR_IMAGE_URI>|g' kubernetes/deployment.yaml

# Apply manifests in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for rollout
kubectl rollout status deployment/acme-portal-static -n acme-portal-static

# Verify
kubectl get pods,svc,ingress -n acme-portal-static
```

---

## 5. Kubernetes Manifest Reference

| File | Kind | Description |
|------|------|-------------|
| `kubernetes/namespace.yaml` | Namespace | Isolates resources under `acme-portal-static` |
| `kubernetes/deployment.yaml` | Deployment | 2 replicas, liveness/readiness on `/api/health` |
| `kubernetes/service.yaml` | Service (ClusterIP) | Internal service on port 80 → 8080 |
| `kubernetes/ingress.yaml` | Ingress (ALB) | Internet-facing ALB, routes `/` to the service |

### Environment Variables (deployment.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Application listening port |
| `JAVA_OPTS` | See manifest | JVM tuning flags |

---

## 6. Scaling and Updates

### Horizontal Scaling

```bash
kubectl scale deployment acme-portal-static --replicas=4 -n acme-portal-static
```

### Rolling Update (new image)

```bash
kubectl set image deployment/acme-portal-static \
  acme-portal-static=<NEW_IMAGE_URI> \
  -n acme-portal-static

kubectl rollout status deployment/acme-portal-static -n acme-portal-static
```

### Rollback

```bash
kubectl rollout undo deployment/acme-portal-static -n acme-portal-static
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment acme-portal-static \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n acme-portal-static
```

---

## 7. Troubleshooting

### Pods not starting

```bash
kubectl describe pod -l app=acme-portal-static -n acme-portal-static
kubectl logs -l app=acme-portal-static -n acme-portal-static --previous
```

### Health check failures

```bash
# Exec into a pod and test the health endpoint
kubectl exec -it <pod-name> -n acme-portal-static -- \
  java -cp app.jar com.trianz.acmeportal.Application &
# Or check logs for startup errors
kubectl logs <pod-name> -n acme-portal-static
```

### Ingress / ALB not provisioning

```bash
kubectl describe ingress acme-portal-static-ingress -n acme-portal-static
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Image pull errors

```bash
# Verify ECR credentials are attached to the node IAM role
aws iam get-role --role-name <node-instance-role>
# Ensure AmazonEC2ContainerRegistryReadOnly policy is attached
```

---

## 8. Security Considerations

- The container runs as a **non-root user** (`appuser`, UID 1000).
- `runAsNonRoot: true` is enforced in the pod security context.
- Secrets (API keys, passwords) should be stored in **AWS Secrets Manager** or **Kubernetes Secrets** and injected as environment variables — never hard-coded.
- Use **IAM Roles for Service Accounts (IRSA)** for fine-grained AWS permissions.
- Enable **ECR image scanning** to detect vulnerabilities before deployment.
- Restrict ingress to known CIDR ranges using ALB security group rules.

---

## 9. Java-Specific Notes

- **JVM flags** (`JAVA_OPTS`) use `-XX:+UseContainerSupport` and `-XX:MaxRAMPercentage=75.0` so the JVM respects container memory limits automatically.
- The application uses the built-in JDK `com.sun.net.httpserver.HttpServer` — no external framework dependencies.
- Health endpoint: `GET /api/health` → `{"status":"ok"}` (HTTP 200).
- Startup time is fast (~1–2 s) because there is no Spring context to initialize; `initialDelaySeconds: 15` in the readiness probe is conservative.
- To change the listening port, update the `PORT` environment variable in `kubernetes/deployment.yaml` and `docker-compose.yml`, and update `containerPort` / `targetPort` accordingly.
