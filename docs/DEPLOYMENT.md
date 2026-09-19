# Deployment Guide — acme-portal-static on GCP GKE

## Overview

This guide covers building, pushing, and deploying the **acme-portal-static** Java application to **Google Kubernetes Engine (GKE)**.

| Property | Value |
|---|---|
| Application | acme-portal-static |
| Language | Java 17 |
| Build Tool | Maven 3.9.x |
| Runtime Base Image | eclipse-temurin:17-jdk |
| Application Port | 8080 |
| Health Endpoint | `/api/health` |
| Target Platform | GCP GKE |

---

## Prerequisites

### Local Tools Required

| Tool | Version | Install |
|---|---|---|
| Docker | 24.x+ | https://docs.docker.com/get-docker/ |
| gcloud CLI | Latest | https://cloud.google.com/sdk/docs/install |
| kubectl | 1.28+ | `gcloud components install kubectl` |
| Java JDK | 17+ | https://adoptium.net/ |
| Maven | 3.9.x+ | https://maven.apache.org/download.cgi |

### GCP Requirements

- A GCP project with billing enabled
- GKE API enabled: `gcloud services enable container.googleapis.com`
- Artifact Registry API enabled: `gcloud services enable artifactregistry.googleapis.com`
- Appropriate IAM roles: `roles/container.developer`, `roles/artifactregistry.writer`

---

## 1. Local Development Setup

### Build the Application Locally

```bash
# From repository root
mvn clean package -DskipTests

# Run locally
java -jar target/acme-portal-static.jar
# Application starts on http://localhost:8080
# Health check: http://localhost:8080/api/health
```

### Run with Docker Compose

```bash
# Build and start the application container
docker compose up --build

# Run in background
docker compose up -d --build

# View logs
docker compose logs -f acme-portal-static

# Stop
docker compose down
```

The application will be available at:
- **Application**: http://localhost:8080
- **Health Check**: http://localhost:8080/api/health

---

## 2. Build and Push Docker Image

### Using the Build Script (Linux/macOS)

```bash
# Make the script executable
chmod +x scripts/build-push.sh

# Run from repository root
./scripts/build-push.sh
```

The script will prompt you to:
1. Enter an image tag (default: `latest`)
2. Select a registry (Google Artifact Registry or Docker Hub)
3. Provide registry credentials

### Using the Build Script (Windows)

```cmd
scripts\build-push.bat
```

### Manual Build and Push (Google Artifact Registry)

```bash
# Authenticate
gcloud auth login
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build
docker build -t us-central1-docker.pkg.dev/YOUR_PROJECT/YOUR_REPO/acme-portal-static:latest .

# Push
docker push us-central1-docker.pkg.dev/YOUR_PROJECT/YOUR_REPO/acme-portal-static:latest
```

### Create Artifact Registry Repository (if not exists)

```bash
gcloud artifacts repositories create acme-portal-static \
  --repository-format=docker \
  --location=us-central1 \
  --description="acme-portal-static container images"
```

---

## 3. GCP GKE Cluster Setup

### Create a GKE Cluster (if not exists)

```bash
# Standard cluster
gcloud container clusters create acme-portal-cluster \
  --zone us-central1-a \
  --num-nodes 2 \
  --machine-type e2-standard-2 \
  --project YOUR_PROJECT_ID

# Or Autopilot cluster (recommended)
gcloud container clusters create-auto acme-portal-cluster \
  --region us-central1 \
  --project YOUR_PROJECT_ID
```

### Configure kubectl

```bash
gcloud container clusters get-credentials acme-portal-cluster \
  --zone us-central1-a \
  --project YOUR_PROJECT_ID

# Verify connectivity
kubectl cluster-info
kubectl get nodes
```

---

## 4. Kubernetes Deployment

### Using the Deploy Script (Linux/macOS)

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- GCP Project ID
- GCP Zone
- GKE Cluster Name
- Full Docker image URI (e.g., `us-central1-docker.pkg.dev/my-project/my-repo/acme-portal-static:latest`)
- Optional: `API_URL` environment variable value

### Using the Deploy Script (Windows)

```cmd
scripts\deploy-image.bat
```

### Manual Kubernetes Deployment

```bash
# 1. Update the image URI in deployment.yaml
sed -i 's|{{IMAGE_URI}}|us-central1-docker.pkg.dev/YOUR_PROJECT/YOUR_REPO/acme-portal-static:latest|g' kubernetes/deployment.yaml
sed -i 's|{{API_URL}}|https://api.example.com|g' kubernetes/deployment.yaml

# 2. Apply manifests in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# 3. Wait for rollout
kubectl rollout status deployment/acme-portal-static -n acme-portal-static

# 4. Verify
kubectl get pods,svc,ingress -n acme-portal-static
```

### Kubernetes Manifest Descriptions

| File | Description |
|---|---|
| `kubernetes/namespace.yaml` | Creates the `acme-portal-static` namespace |
| `kubernetes/deployment.yaml` | Deploys 2 replicas with health probes and resource limits |
| `kubernetes/service.yaml` | ClusterIP service exposing port 80 → 8080 |
| `kubernetes/ingress.yaml` | GKE Ingress with GCE controller for external access |

---

## 5. Configuration Management

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | Application listening port |
| `JAVA_OPTS` | See Dockerfile | JVM tuning flags |
| `API_URL` | *(empty)* | Backend API base URL used by frontend |

### Updating Configuration

```bash
# Update a deployment environment variable
kubectl set env deployment/acme-portal-static \
  API_URL=https://api.example.com \
  -n acme-portal-static

# Or edit the deployment directly
kubectl edit deployment/acme-portal-static -n acme-portal-static
```

### Using Kubernetes Secrets

```bash
# Create a secret
kubectl create secret generic acme-portal-secrets \
  --from-literal=API_KEY=your-api-key \
  -n acme-portal-static

# Reference in deployment.yaml under env:
# - name: API_KEY
#   valueFrom:
#     secretKeyRef:
#       name: acme-portal-secrets
#       key: API_KEY
```

---

## 6. Scaling and Management

### Manual Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment/acme-portal-static --replicas=3 -n acme-portal-static
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment/acme-portal-static \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n acme-portal-static
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/acme-portal-static \
  acme-portal-static=us-central1-docker.pkg.dev/YOUR_PROJECT/YOUR_REPO/acme-portal-static:v2.0.0 \
  -n acme-portal-static

# Monitor rollout
kubectl rollout status deployment/acme-portal-static -n acme-portal-static
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/acme-portal-static -n acme-portal-static

# Rollback to specific revision
kubectl rollout history deployment/acme-portal-static -n acme-portal-static
kubectl rollout undo deployment/acme-portal-static --to-revision=2 -n acme-portal-static
```

---

## 7. Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n acme-portal-static
kubectl describe pod <pod-name> -n acme-portal-static
kubectl logs <pod-name> -n acme-portal-static
kubectl logs <pod-name> -n acme-portal-static --previous  # crashed pod logs
```

### Common Issues

#### Pods in CrashLoopBackOff
```bash
# Check logs for startup errors
kubectl logs <pod-name> -n acme-portal-static

# Common causes:
# - Incorrect image URI
# - Missing environment variables
# - Insufficient memory (increase resources.limits.memory)
```

#### Pods in ImagePullBackOff
```bash
# Verify image exists
docker pull us-central1-docker.pkg.dev/YOUR_PROJECT/YOUR_REPO/acme-portal-static:latest

# Check GKE node service account has Artifact Registry access
gcloud projects add-iam-policy-binding YOUR_PROJECT \
  --member="serviceAccount:YOUR_NODE_SA@YOUR_PROJECT.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

#### Health Probe Failures
```bash
# Test health endpoint from within the cluster
kubectl exec -it <pod-name> -n acme-portal-static -- \
  sh -c 'wget -qO- http://localhost:8080/api/health'

# Expected response: {"status":"ok"}
```

#### Ingress Not Getting External IP
```bash
# Check ingress events
kubectl describe ingress acme-portal-static-ingress -n acme-portal-static

# GKE Ingress provisioning can take 2-5 minutes
kubectl get ingress -n acme-portal-static -w
```

### Resource Monitoring

```bash
# Pod resource usage
kubectl top pods -n acme-portal-static

# Node resource usage
kubectl top nodes
```

---

## 8. Security Considerations

- **Non-root user**: The container runs as `appuser` (non-root) for GKE security compliance
- **Read-only filesystem**: Consider enabling `readOnlyRootFilesystem: true` if no runtime writes are needed
- **Network policies**: Apply Kubernetes NetworkPolicy to restrict pod-to-pod communication
- **Secrets management**: Use GCP Secret Manager or Kubernetes Secrets for sensitive values — never hardcode credentials
- **Image scanning**: Enable Artifact Registry vulnerability scanning for the repository
- **RBAC**: Apply least-privilege RBAC roles for service accounts
- **Resource limits**: CPU and memory limits are set to prevent noisy-neighbour issues

---

## 9. Java-Specific Notes

### JVM Container Awareness

The application uses the following JVM flags (set via `JAVA_OPTS`):

```
-XX:+UseContainerSupport        # Respect container CPU/memory limits
-XX:MaxRAMPercentage=75.0       # Use 75% of container memory for heap
-XX:+UnlockExperimentalVMOptions
-Xms256m                        # Initial heap size
-Xmx512m                        # Maximum heap size
-Dfile.encoding=UTF-8
-Duser.timezone=UTC
```

### Adjusting Memory

If the application is OOMKilled, increase the memory limit in `kubernetes/deployment.yaml`:

```yaml
resources:
  requests:
    memory: "512Mi"
  limits:
    memory: "1Gi"   # Increase this value
```

Also update `JAVA_OPTS` accordingly:
```yaml
- name: JAVA_OPTS
  value: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms512m -Xmx768m ..."
```

### Health Check Endpoint

The application exposes `GET /api/health` which returns:
```json
{"status":"ok"}
```

This endpoint is used by both Kubernetes liveness and readiness probes.

---

## 10. Quick Reference

```bash
# Build image
docker build -t acme-portal-static:latest .

# Run locally
docker run -p 8080:8080 acme-portal-static:latest

# Deploy to GKE
./scripts/deploy-image.sh

# Check deployment status
kubectl get all -n acme-portal-static

# View logs
kubectl logs -l app=acme-portal-static -n acme-portal-static --tail=100

# Rollback
kubectl rollout undo deployment/acme-portal-static -n acme-portal-static
```
