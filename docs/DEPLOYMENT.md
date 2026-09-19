# Deployment Guide — csat (acme-portal-static)

## Overview

This guide covers building, pushing, and deploying the **csat** application (acme-portal-static) to **AWS EKS** using Docker and Kubernetes.

- **Application**: acme-portal-static — static multi-page portal with a lightweight Java HTTP backend
- **Backend**: Java 17, plain JDK `HttpServer` (no Spring Boot), exposes `GET /api/health`
- **Build Tool**: Maven 3.9.x (system `mvn` — no wrapper)
- **Port**: 8080
- **Health Endpoint**: `/api/health`
- **Base Image (runtime)**: `eclipse-temurin:17-jdk`

---

## Prerequisites

### Local Development
| Tool | Version | Notes |
|------|---------|-------|
| Docker | 24+ | For building and running containers |
| Docker Compose | 2.x | For local multi-container orchestration |
| Java JDK | 17 | For local builds outside Docker |
| Maven | 3.9.x | For local builds outside Docker |

### AWS EKS Deployment
| Tool | Version | Notes |
|------|---------|-------|
| AWS CLI | 2.x | Configured with appropriate IAM permissions |
| kubectl | 1.28+ | Kubernetes CLI |
| eksctl | 0.160+ | EKS cluster management (optional) |

### Required IAM Permissions
- `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:CreateRepository`
- `eks:DescribeCluster`, `eks:ListClusters`
- `sts:GetCallerIdentity`

---

## Project Structure

```
Csat/
├── Dockerfile                  # Multi-stage build (Maven builder + eclipse-temurin:17-jdk runtime)
├── .dockerignore               # Excludes target/, wrapper files, dev HTML, source maps
├── docker-compose.yml          # Local development (application only)
├── pom.xml                     # Maven build descriptor
├── src/                        # Java source (Application.java, HealthHandler.java)
├── index.html                  # Production static assets
├── app/, forms/, pages/, partials/, assets/
├── kubernetes/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── build-push.sh           # Linux/macOS: build & push to ECR or Docker Hub
│   ├── build-push.bat          # Windows: build & push to ECR or Docker Hub
│   ├── deploy-image.sh         # Linux/macOS: deploy to AWS EKS
│   └── deploy-image.bat        # Windows: deploy to AWS EKS
└── docs/
    └── DEPLOYMENT.md           # This file
```

---

## Local Development with Docker Compose

### 1. Build and start the application

```bash
# From the Csat/ directory
docker compose up --build
```

### 2. Verify the application

```bash
# Health check
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}

# Static portal
open http://localhost:8080
```

### 3. Stop the application

```bash
docker compose down
```

### Environment Variables (docker-compose.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_OPTS` | `-Xmx512m -Xms256m ...` | JVM tuning flags |
| `TZ` | `UTC` | Container timezone |
| `API_URL` | `http://localhost:8080` | Backend API base URL for frontend |

---

## Building and Pushing the Docker Image

### Linux / macOS

```bash
# From the Csat/ directory (repo root)
bash scripts/build-push.sh
```

The script will prompt for:
1. Registry type (AWS ECR or Docker Hub)
2. Image tag (defaults to `latest`)
3. Registry credentials / AWS details

### Windows

```cmd
scripts\build-push.bat
```

### Manual Build (ECR example)

```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
IMAGE_TAG=1.0.0

# Authenticate
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repository (first time only)
aws ecr create-repository --repository-name csat --region $AWS_REGION

# Build and push
docker build -f Dockerfile \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/csat:${IMAGE_TAG} .

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/csat:${IMAGE_TAG}
```

---

## AWS EKS Deployment

### Step 1: Configure AWS CLI

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### Step 2: Connect to EKS Cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl cluster-info
```

### Step 3: Deploy using the script

#### Linux / macOS

```bash
bash scripts/deploy-image.sh
```

The script will prompt for:
- AWS region
- EKS cluster name
- Full Docker image URI (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/csat:1.0.0`)
- Optional: `API_URL` environment variable value

#### Windows

```cmd
scripts\deploy-image.bat
```

### Step 4: Manual Deployment (alternative)

```bash
# Set image URI in deployment manifest
sed -i 's|{{IMAGE_URI}}|123456789012.dkr.ecr.us-east-1.amazonaws.com/csat:1.0.0|g' kubernetes/deployment.yaml
sed -i 's|{{API_URL}}|https://api.example.com|g' kubernetes/deployment.yaml

# Apply manifests
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for rollout
kubectl rollout status deployment/csat -n csat --timeout=300s

# Verify
kubectl get pods,svc,ingress -n csat
```

---

## Kubernetes Manifest Descriptions

### namespace.yaml
Creates the `csat` Kubernetes namespace to isolate all application resources.

### deployment.yaml
- **Replicas**: 2 (high availability)
- **Image**: Placeholder `{{IMAGE_URI}}` replaced at deploy time
- **Resources**: requests `250m CPU / 512Mi RAM`, limits `500m CPU / 1Gi RAM`
- **Liveness Probe**: `GET /api/health` on port 8080, starts after 30s
- **Readiness Probe**: `GET /api/health` on port 8080, starts after 15s
- **Security**: Non-root user, drops all Linux capabilities
- **JVM Flags**: Container-aware heap sizing via `JAVA_OPTS`

### service.yaml
- **Type**: `ClusterIP` — internal cluster access only
- **Port mapping**: `80 → 8080`
- Routes traffic to pods with label `app: csat`

### ingress.yaml
- **Controller**: AWS Load Balancer Controller (ALB)
- **Scheme**: `internet-facing`
- **Target type**: `ip` (direct pod routing)
- **Health check path**: `/api/health`
- **Host**: `csat.example.com` — update to your actual domain

---

## EKS Cluster Setup (if needed)

### Create a new EKS cluster with eksctl

```bash
eksctl create cluster \
  --name csat-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

### Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=csat-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## Scaling and Management

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment csat \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n csat
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/csat \
  csat=123456789012.dkr.ecr.us-east-1.amazonaws.com/csat:2.0.0 \
  -n csat

# Monitor rollout
kubectl rollout status deployment/csat -n csat
```

### Rollback

```bash
kubectl rollout undo deployment/csat -n csat

# Rollback to specific revision
kubectl rollout undo deployment/csat --to-revision=2 -n csat

# View rollout history
kubectl rollout history deployment/csat -n csat
```

---

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl get pods -n csat

# Describe pod for events
kubectl describe pod <pod-name> -n csat

# View logs
kubectl logs <pod-name> -n csat
kubectl logs <pod-name> -n csat --previous  # crashed pod logs
```

### Health check failing

```bash
# Port-forward to test locally
kubectl port-forward deployment/csat 8080:8080 -n csat

# Test health endpoint
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### Ingress not getting an address

```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check ingress events
kubectl describe ingress csat-ingress -n csat
```

### Image pull errors

```bash
# Verify ECR authentication
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Check if image exists
aws ecr describe-images --repository-name csat --region us-east-1
```

### OOMKilled (Out of Memory)

Increase memory limits in `kubernetes/deployment.yaml`:
```yaml
resources:
  limits:
    memory: "2Gi"
```
Or tune JVM heap in `JAVA_OPTS`:
```
-Xmx1g -Xms512m
```

---

## Security Considerations

1. **Non-root container**: The application runs as `appuser` (UID 1000)
2. **Read-only filesystem**: Consider enabling `readOnlyRootFilesystem: true` if no runtime writes are needed
3. **Capability dropping**: All Linux capabilities are dropped
4. **Secrets management**: Use AWS Secrets Manager or Kubernetes Secrets for sensitive values — never hardcode credentials
5. **Network policies**: Apply Kubernetes NetworkPolicy to restrict pod-to-pod communication
6. **Image scanning**: Enable ECR image scanning on push for vulnerability detection
7. **IRSA**: Use IAM Roles for Service Accounts (IRSA) instead of node-level IAM roles

---

## Java-Specific Notes

- **JVM Container Support**: `-XX:+UseContainerSupport` ensures the JVM respects container memory limits (Java 11+)
- **MaxRAMPercentage**: Set to `75.0` — JVM uses up to 75% of container memory for heap
- **Startup time**: The plain JDK `HttpServer` starts in milliseconds; `initialDelaySeconds: 15` for readiness is conservative
- **No Spring Boot**: This application uses only built-in JDK APIs — no Spring context, no Actuator. Health endpoint is `/api/health`
- **Graceful shutdown**: `terminationGracePeriodSeconds: 30` allows in-flight requests to complete
- **Timezone**: Set to `UTC` via `TZ` environment variable for consistent log timestamps

---

## Configuration Reference

| Parameter | Value | Source |
|-----------|-------|--------|
| Application port | `8080` | `Application.java` |
| Health endpoint | `/api/health` | `HealthHandler.java` |
| Java version | `17` | `pom.xml` |
| Build tool | `Maven 3.9.x` | `pom.xml` |
| Artifact | `target/acme-portal-static.jar` | `pom.xml` (finalName) |
| Runtime base image | `eclipse-temurin:17-jdk` | Explicit parameter |
| Builder base image | `maven:3.9.4-eclipse-temurin-17` | Auto-selected |
