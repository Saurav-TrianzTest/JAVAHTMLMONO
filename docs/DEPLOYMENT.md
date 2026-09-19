# Deployment Guide – acme-portal-static on Azure AKS

## Overview

This guide covers building, pushing, and deploying the **acme-portal-static** Java application to **Azure Kubernetes Service (AKS)**.

- **Application**: acme-portal-static
- **Technology**: Java 17, plain JDK HttpServer (no Spring Boot)
- **Build Tool**: Maven 3.9.x
- **Port**: 8080
- **Health Endpoint**: `GET /api/health`
- **Base Image (runtime)**: `eclipse-temurin:17-jdk`

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Java JDK | 17+ | Local build/run |
| Maven | 3.9+ | Build tool |
| Docker | 24+ | Container build/run |
| Docker Compose | 2.x | Local multi-container orchestration |

### Azure AKS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| Azure CLI | 2.50+ | Azure resource management |
| kubectl | 1.27+ | Kubernetes cluster management |
| Azure Subscription | – | AKS cluster hosting |

---

## Project Structure

```
Repo-Azure/
├── Dockerfile                  # Multi-stage Docker build
├── docker-compose.yml          # Local development compose
├── .dockerignore               # Docker build context exclusions
├── pom.xml                     # Maven build descriptor
├── src/
│   └── main/java/com/trianz/acmeportal/
│       ├── Application.java    # Main entry point (port 8080)
│       └── HealthHandler.java  # GET /api/health handler
├── index.html                  # Static frontend entry
├── app/                        # SPA shell pages
├── pages/                      # Static page templates
├── forms/                      # Form pages
├── partials/                   # Reusable HTML partials
├── assets/                     # CSS, JS, images
├── kubernetes/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── build-push.sh           # Linux/macOS build & push
│   ├── build-push.bat          # Windows build & push
│   ├── deploy-image.sh         # Linux/macOS AKS deploy
│   └── deploy-image.bat        # Windows AKS deploy
└── docs/
    └── DEPLOYMENT.md           # This file
```

---

## 1. Local Development Setup

### Build and Run with Maven

```bash
# Build the JAR
mvn clean package -DskipTests

# Run locally
java -jar target/acme-portal-static.jar
# Application starts on http://localhost:8080
# Health check: http://localhost:8080/api/health
```

### Build and Run with Docker Compose

```bash
# Build and start the application container
docker compose up --build

# Run in background
docker compose up --build -d

# View logs
docker compose logs -f acme-portal-static

# Stop
docker compose down
```

The application will be available at:
- **Application**: http://localhost:8080
- **Health**: http://localhost:8080/api/health

### Environment Variables (docker-compose.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_OPTS` | JVM container flags | JVM tuning options |
| `API_URL` | `http://localhost:8080` | Backend API base URL |

---

## 2. Build and Push Docker Image

### Linux / macOS

```bash
# Make script executable
chmod +x scripts/build-push.sh

# Run from repository root
bash scripts/build-push.sh
```

### Windows

```cmd
REM Run from repository root
scripts\build-push.bat
```

The script will prompt you to:
1. Choose registry type: **Azure ACR** or **Docker Hub**
2. Enter registry credentials
3. Enter an image tag (defaults to `latest`)

The script then:
- Sanitizes the image name (lowercase, hyphenated)
- Authenticates to the selected registry
- Builds the Docker image from the repository root
- Pushes the image to the registry

### Manual Build

```bash
# Build image
docker build -t myregistry.azurecr.io/acme-portal-static:latest .

# Push image
docker push myregistry.azurecr.io/acme-portal-static:latest
```

---

## 3. Azure AKS Prerequisites

### Install Azure CLI

```bash
# macOS
brew install azure-cli

# Linux (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows – download from https://aka.ms/installazurecliwindows
```

### Install kubectl

```bash
# macOS
brew install kubectl

# Linux
sudo az aks install-cli

# Windows
az aks install-cli
```

### Login to Azure

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

### Create AKS Cluster (if not existing)

```bash
# Create resource group
az group create --name my-resource-group --location eastus

# Create AKS cluster with Application Gateway Ingress Controller
az aks create \
  --resource-group my-resource-group \
  --name my-aks-cluster \
  --node-count 2 \
  --enable-addons ingress-appgw \
  --appgw-name my-app-gateway \
  --appgw-subnet-cidr "10.225.0.0/16" \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group my-resource-group --name my-aks-cluster
```

### Create Azure Container Registry (ACR)

```bash
# Create ACR
az acr create --resource-group my-resource-group --name myregistry --sku Basic

# Attach ACR to AKS (allows AKS to pull images)
az aks update --resource-group my-resource-group --name my-aks-cluster --attach-acr myregistry
```

---

## 4. Deploy to Azure AKS

### Linux / macOS

```bash
chmod +x scripts/deploy-image.sh
bash scripts/deploy-image.sh
```

### Windows

```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- **Azure Resource Group**: The resource group containing your AKS cluster
- **AKS Cluster Name**: Your AKS cluster name
- **Docker Image URI**: Full image path with tag (e.g., `myregistry.azurecr.io/acme-portal-static:latest`)
- **API_URL** (optional): Backend API base URL

The script then:
1. Configures `kubectl` with AKS credentials
2. Verifies cluster connectivity
3. Replaces `{{IMAGE_URI}}` and `{{API_URL}}` placeholders in manifests
4. Applies manifests in order: namespace → deployment → service → ingress
5. Waits for deployment rollout
6. Displays deployed resources and application URL

### Manual Deployment

```bash
# Configure kubectl
az aks get-credentials --resource-group my-resource-group --name my-aks-cluster

# Update image in deployment.yaml (replace placeholder)
sed -i 's|{{IMAGE_URI}}|myregistry.azurecr.io/acme-portal-static:latest|g' kubernetes/deployment.yaml
sed -i 's|{{API_URL}}|https://api.example.com|g' kubernetes/deployment.yaml

# Apply manifests
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

## 5. Kubernetes Manifest Descriptions

### namespace.yaml
Creates the `acme-portal-static` namespace to isolate all application resources.

### deployment.yaml
Deploys 2 replicas of the application with:
- **Image**: Pulled from `{{IMAGE_URI}}` (replaced at deploy time)
- **Resources**: 250m CPU / 512Mi memory (requests); 500m CPU / 1Gi memory (limits)
- **Liveness Probe**: `GET /api/health` every 30s (starts after 20s)
- **Readiness Probe**: `GET /api/health` every 15s (starts after 15s)
- **Security**: Non-root user, dropped Linux capabilities

### service.yaml
ClusterIP service exposing port 80 → container port 8080.

### ingress.yaml
Azure Application Gateway Ingress Controller (AGIC) ingress:
- Host: `acme-portal-static.example.com` (update to your domain)
- Routes all traffic (`/`) to the service on port 80

---

## 6. Configuration Management

### Update Ingress Host

Edit `kubernetes/ingress.yaml` to set your actual domain:

```yaml
spec:
  rules:
    - host: your-actual-domain.com   # ← change this
```

### Environment Variables

Update environment variables in `kubernetes/deployment.yaml`:

```yaml
env:
  - name: API_URL
    value: "https://your-api-endpoint.com"
```

For sensitive values, use Kubernetes Secrets:

```bash
kubectl create secret generic acme-portal-secrets \
  --from-literal=API_KEY=your-secret-key \
  -n acme-portal-static
```

Then reference in deployment.yaml:
```yaml
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: acme-portal-secrets
        key: API_KEY
```

---

## 7. AKS Scaling and Management

### Manual Scaling

```bash
kubectl scale deployment acme-portal-static --replicas=3 -n acme-portal-static
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment acme-portal-static \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n acme-portal-static
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/acme-portal-static \
  acme-portal-static=myregistry.azurecr.io/acme-portal-static:v2.0.0 \
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

## 8. Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n acme-portal-static

# Describe pod for events
kubectl describe pod <pod-name> -n acme-portal-static

# View pod logs
kubectl logs <pod-name> -n acme-portal-static
kubectl logs -l app=acme-portal-static -n acme-portal-static
```

### Image Pull Errors

```bash
# Verify ACR attachment to AKS
az aks check-acr --resource-group my-resource-group --name my-aks-cluster --acr myregistry

# Re-attach ACR if needed
az aks update --resource-group my-resource-group --name my-aks-cluster --attach-acr myregistry
```

### Health Check Failures

```bash
# Test health endpoint from within cluster
kubectl run test-pod --image=busybox --restart=Never -n acme-portal-static -- \
  wget -qO- http://acme-portal-static-service/api/health

# Check service endpoints
kubectl get endpoints acme-portal-static-service -n acme-portal-static
```

### Ingress Not Accessible

```bash
# Check ingress status
kubectl describe ingress acme-portal-static-ingress -n acme-portal-static

# Check Application Gateway status
az network application-gateway show \
  --resource-group my-resource-group \
  --name my-app-gateway \
  --query "operationalState"

# Get ingress IP
kubectl get ingress acme-portal-static-ingress -n acme-portal-static
```

### JVM Memory Issues

```bash
# Check container resource usage
kubectl top pods -n acme-portal-static

# Adjust JAVA_OPTS in deployment.yaml if OOMKilled
# Increase memory limits or tune MaxRAMPercentage
```

---

## 9. Security Considerations

1. **Non-root container**: The application runs as `appuser` (non-root) inside the container.
2. **Read-only filesystem**: Consider enabling `readOnlyRootFilesystem: true` if the app doesn't write to disk.
3. **Dropped capabilities**: All Linux capabilities are dropped (`capabilities.drop: [ALL]`).
4. **Secrets management**: Use Kubernetes Secrets or Azure Key Vault for sensitive configuration.
5. **Network policies**: Consider adding Kubernetes NetworkPolicy to restrict pod-to-pod communication.
6. **Image scanning**: Scan images with `az acr task run` or integrate with Microsoft Defender for Containers.
7. **RBAC**: Use Azure RBAC and Kubernetes RBAC to restrict access to the cluster.
8. **TLS**: Configure TLS termination at the Application Gateway level for HTTPS.

---

## 10. Java-Specific Notes

### JVM Container Awareness

The application uses these JVM flags (set via `JAVA_OPTS`):

```
-XX:+UseContainerSupport          # Respect container CPU/memory limits
-XX:MaxRAMPercentage=75.0         # Use 75% of container memory for heap
-XX:+UnlockExperimentalVMOptions  # Enable experimental JVM features
-Djava.security.egd=file:/dev/./urandom  # Faster random number generation
-Dfile.encoding=UTF-8             # Consistent character encoding
-Duser.timezone=UTC               # Consistent timezone
```

### Graceful Shutdown

The JDK `HttpServer` handles `SIGTERM` via the JVM shutdown hook. The Kubernetes `terminationGracePeriodSeconds: 30` allows 30 seconds for in-flight requests to complete.

### No Spring Boot Actuator

This application uses a plain JDK `HttpServer` (no Spring Boot). The health endpoint is:
- `GET /api/health` → returns `{"status":"ok"}` with HTTP 200

This endpoint is used for both liveness and readiness probes in the Kubernetes deployment.

---

## Quick Reference

```bash
# Build & push image
bash scripts/build-push.sh

# Deploy to AKS
bash scripts/deploy-image.sh

# Check deployment status
kubectl get pods,svc,ingress -n acme-portal-static

# View logs
kubectl logs -l app=acme-portal-static -n acme-portal-static -f

# Scale up
kubectl scale deployment acme-portal-static --replicas=3 -n acme-portal-static

# Rollback
kubectl rollout undo deployment/acme-portal-static -n acme-portal-static
```
