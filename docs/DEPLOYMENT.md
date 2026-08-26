# Deployment Guide – acme-portal-static on AWS EKS

## Overview

This guide covers building, pushing, and deploying the **acme-portal-static** Java application to AWS Elastic Kubernetes Service (EKS).

- **Application**: acme-portal-static (com.trianz.acmeportal)
- **Java Version**: 17
- **Build Tool**: Maven 3.9.x
- **Runtime Base Image**: mcr.microsoft.com/openjdk/jdk:17-ubuntu
- **Application Port**: 8080
- **Health Endpoint**: `GET /api/health` → `{"status":"ok"}`
- **Target Platform**: AWS EKS (Kubernetes)

---

## Prerequisites

### Local Development
- Docker Desktop 24+ (with BuildKit enabled)
- Java 17 JDK (for local builds)
- Maven 3.9+ (for local builds)

### AWS EKS Deployment
- AWS CLI v2 (`aws --version`)
- kubectl v1.28+ (`kubectl version --client`)
- eksctl (optional, for cluster creation)
- IAM permissions:
  - `ecr:GetAuthorizationToken`, `ecr:CreateRepository`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`
  - `eks:DescribeCluster`, `eks:UpdateKubeconfig`
  - `elasticloadbalancing:*` (for ALB Ingress Controller)

---

## Project Structure

```
RgJAVAHTMLMONO/
├── Dockerfile                  # Multi-stage build (Maven builder + MS OpenJDK runtime)
├── docker-compose.yml          # Local development compose (app only)
├── .dockerignore               # Excludes build artifacts, wrappers, dev files
├── pom.xml                     # Maven build descriptor
├── src/                        # Java source code
│   └── main/java/com/trianz/acmeportal/
│       ├── Application.java    # Main entry point (JDK HttpServer on :8080)
│       └── HealthHandler.java  # GET /api/health handler
├── index.html                  # Production HTML assets
├── app/, pages/, partials/, forms/
├── assets/css/site.css
├── kubernetes/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── build-push.sh           # Linux/macOS build & push
│   ├── build-push.bat          # Windows build & push
│   ├── deploy-image.sh         # Linux/macOS EKS deploy
│   └── deploy-image.bat        # Windows EKS deploy
└── docs/
    └── DEPLOYMENT.md           # This file
```

---

## 1. Local Development with Docker Compose

### Build and run locally

```bash
# Build and start the application container
docker compose up --build

# Access the application
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}

# Stop the application
docker compose down
```

### Environment variables (docker-compose.yml)

| Variable    | Default                  | Description                    |
|-------------|--------------------------|--------------------------------|
| `TZ`        | `UTC`                    | Container timezone             |
| `JAVA_OPTS` | `-Xms256m -Xmx512m ...`  | JVM memory and container flags |
| `API_URL`   | `http://localhost:8080`  | Backend API base URL           |

---

## 2. Build and Push Docker Image

### Linux / macOS

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

The script will prompt you to:
1. Enter an image tag (defaults to `latest`)
2. Select registry: **1. AWS ECR** or **2. Docker Hub**
3. Provide registry credentials/details

**AWS ECR flow:**
- Prompts for AWS Region and Account ID
- Automatically creates the ECR repository if it does not exist
- Authenticates via `aws ecr get-login-password`
- Builds and pushes the image

**Docker Hub flow:**
- Prompts for username, password/token, and repository name
- Authenticates and pushes the image

---

## 3. AWS EKS Prerequisites

### 3.1 Install and configure AWS CLI

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### 3.2 Install kubectl

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

### 3.3 Configure kubectl for your EKS cluster

```bash
aws eks update-kubeconfig --region <AWS_REGION> --name <CLUSTER_NAME>
kubectl cluster-info
```

### 3.4 Install AWS Load Balancer Controller (for Ingress)

The ingress manifest uses the AWS ALB Ingress Controller. Install it on your cluster:

```bash
# Add the EKS chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<CLUSTER_NAME> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 4. Deploy to AWS EKS

### Linux / macOS

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

### Windows

```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- **AWS Region** (e.g., `us-east-1`)
- **EKS Cluster Name**
- **Full Docker image URI** (e.g., `123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest`)
- **API_URL** (optional, defaults to `http://localhost:8080`)

The script then:
1. Configures `kubectl` for the EKS cluster
2. Substitutes `{{IMAGE_URI}}` and `{{API_URL}}` placeholders in `kubernetes/deployment.yaml`
3. Applies manifests in order: namespace → deployment → service → ingress
4. Waits for the deployment rollout to complete
5. Displays the ALB ingress hostname

---

## 5. Kubernetes Manifest Reference

### namespace.yaml
Creates the `acme-portal-static` namespace to isolate all resources.

### deployment.yaml
- **Replicas**: 2 (high availability)
- **Image**: `{{IMAGE_URI}}` (replaced at deploy time)
- **Resources**: requests `250m CPU / 512Mi RAM`, limits `500m CPU / 1Gi RAM`
- **Liveness probe**: `GET /api/health` on port 8080 (initial delay 30s, period 30s)
- **Readiness probe**: `GET /api/health` on port 8080 (initial delay 15s, period 10s)
- **Security**: runs as non-root user (UID 1000)

### service.yaml
- **Type**: ClusterIP (internal cluster access)
- **Port mapping**: 80 → 8080

### ingress.yaml
- **Class**: `alb` (AWS Load Balancer Controller)
- **Scheme**: `internet-facing`
- **Target type**: `ip`
- **Health check path**: `/api/health`
- **Host**: `acme-portal-static.example.com` (update to your actual domain)

---

## 6. Manual kubectl Commands

```bash
# Check pod status
kubectl get pods -n acme-portal-static

# View pod logs
kubectl logs -l app=acme-portal-static -n acme-portal-static --tail=100

# Describe a pod (for troubleshooting)
kubectl describe pod -l app=acme-portal-static -n acme-portal-static

# Check service
kubectl get svc -n acme-portal-static

# Check ingress and ALB hostname
kubectl get ingress -n acme-portal-static

# Port-forward for local testing
kubectl port-forward svc/acme-portal-static-service 8080:80 -n acme-portal-static
curl http://localhost:8080/api/health
```

---

## 7. Scaling and Updates

### Scale replicas

```bash
kubectl scale deployment acme-portal-static --replicas=4 -n acme-portal-static
```

### Rolling update (new image)

```bash
kubectl set image deployment/acme-portal-static \
  acme-portal-static=<NEW_IMAGE_URI> \
  -n acme-portal-static

kubectl rollout status deployment/acme-portal-static -n acme-portal-static
```

### Rollback

```bash
kubectl rollout undo deployment/acme-portal-static -n acme-portal-static
kubectl rollout history deployment/acme-portal-static -n acme-portal-static
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

## 8. Troubleshooting

### Pod stuck in `Pending`
```bash
kubectl describe pod -l app=acme-portal-static -n acme-portal-static
# Check: Insufficient CPU/memory, node selector issues, image pull errors
```

### Pod in `CrashLoopBackOff`
```bash
kubectl logs -l app=acme-portal-static -n acme-portal-static --previous
# Check: Application startup errors, port conflicts, JVM OOM
```

### Image pull errors (`ErrImagePull`)
```bash
# Verify ECR credentials and repository exist
aws ecr describe-repositories --repository-names acme-portal-static
# Ensure EKS node IAM role has ecr:GetAuthorizationToken permission
```

### Ingress not getting an ALB hostname
```bash
kubectl describe ingress acme-portal-static-ingress -n acme-portal-static
# Check: AWS Load Balancer Controller is installed and running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Health check failures
```bash
# Test health endpoint directly
kubectl port-forward svc/acme-portal-static-service 8080:80 -n acme-portal-static
curl -v http://localhost:8080/api/health
# Expected: HTTP 200, body: {"status":"ok"}
```

---

## 9. Security Considerations

- The container runs as a **non-root user** (UID 1000) for security hardening.
- Sensitive values (API keys, secrets) should be stored in **AWS Secrets Manager** or **Kubernetes Secrets**, not in environment variables directly.
- Use **IAM Roles for Service Accounts (IRSA)** to grant pods AWS permissions without static credentials.
- Enable **network policies** to restrict pod-to-pod communication.
- Regularly scan the container image with **Amazon ECR image scanning** or **Trivy**.
- Use **Pod Security Standards** (restricted profile) for production namespaces.

---

## 10. Java-Specific Configuration

### JVM Flags (set via `JAVA_OPTS`)

| Flag | Purpose |
|------|---------|
| `-Xms256m` | Initial heap size |
| `-Xmx512m` | Maximum heap size |
| `-XX:+UseContainerSupport` | Enables JVM container awareness |
| `-XX:MaxRAMPercentage=75.0` | Limits heap to 75% of container memory |
| `-XX:+UnlockExperimentalVMOptions` | Enables experimental JVM features |

### Adjusting memory limits

If you increase the Kubernetes memory limit, update `JAVA_OPTS` accordingly:
```yaml
# For 2Gi memory limit:
- name: JAVA_OPTS
  value: "-Xms512m -Xmx1536m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

### Graceful shutdown

The application uses `terminationGracePeriodSeconds: 30` to allow in-flight requests to complete before the pod is terminated.

---

## 11. Clean Up

```bash
# Remove all resources for this application
kubectl delete namespace acme-portal-static

# Or remove individual resources
kubectl delete -f kubernetes/ -n acme-portal-static
```
