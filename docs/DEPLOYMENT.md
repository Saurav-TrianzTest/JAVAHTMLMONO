# Deployment Guide – acme-portal-static (JAVAHTMLGIT)

## Overview

This guide covers building, running, and deploying the **acme-portal-static** Java application to **AWS ECS Fargate**.

The application is a lightweight Java 17 HTTP server (using the built-in JDK `com.sun.net.httpserver` API) that:
- Serves static HTML assets (pages, forms, partials, app shell)
- Exposes `GET /api/health` for liveness/readiness probes
- Exposes `GET /config/config.json` for runtime configuration injection (window.__ENV__)
- Normalizes HTML path separators and injects environment variables at container startup via `docker-entrypoint.sh`

**Runtime base image**: `mcr.microsoft.com/openjdk/jdk:17-ubuntu`  
**Build tool**: Maven 3.9.4  
**Java version**: 17  
**Application port**: 8080  
**Health endpoint**: `/api/health`

---

## Prerequisites

### Local Development
- Docker Desktop 24+ (or Docker Engine 24+)
- Docker Compose v2.x
- Java 17 JDK (for local builds without Docker)
- Maven 3.9+ (for local builds without Docker)

### AWS ECS Fargate Deployment
- AWS CLI v2 installed and configured (`aws configure`)
- IAM permissions for: ECS, ECR, CloudWatch Logs, ELBv2, IAM (read)
- An existing VPC with at least 2 subnets (preferably in different AZs)
- A security group allowing inbound TCP on port 8080 (and port 80 if using ALB)
- IAM roles:
  - `ecsTaskExecutionRole` – allows ECS to pull images from ECR and write logs to CloudWatch
  - `ecsTaskRole` – optional, for task-level AWS API permissions

---

## Project Structure

```
JAVAHTMLGIT/
├── Dockerfile                    # Multi-stage build (Maven builder + OpenJDK runtime)
├── docker-compose.yml            # Local development compose file
├── .dockerignore                 # Excludes build artifacts and dev files
├── docker-entrypoint.sh          # Path normalization & env injection entrypoint
├── pom.xml                       # Maven build descriptor
├── src/
│   └── main/java/com/trianz/acmeportal/
│       ├── Application.java      # Main entry point (JDK HttpServer on port 8080)
│       ├── HealthHandler.java    # GET /api/health → {"status":"ok"}
│       └── RuntimeConfigHandler.java  # GET /config/config.json
├── pages/                        # HTML pages (dashboard.html, etc.)
├── app/                          # SPA shell HTML
├── assets/                       # CSS, JS, images
├── partials/                     # Reusable HTML partials
├── forms/                        # HTML forms
├── index.html                    # Application entry point
├── ecs/
│   ├── task-definition.json      # ECS Fargate task definition
│   └── service-definition.json   # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS: build & push to ECR or Docker Hub
│   ├── build-push.bat            # Windows: build & push to ECR or Docker Hub
│   ├── deploy-image.sh           # Linux/macOS: deploy to AWS ECS Fargate
│   └── deploy-image.bat          # Windows: deploy to AWS ECS Fargate
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development with Docker Compose

### 1. Build and start the application

```bash
# From the repository root
docker compose up --build
```

The application will be available at: http://localhost:8080

### 2. Test health endpoint

```bash
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### 3. Test runtime config endpoint

```bash
curl http://localhost:8080/config/config.json
# Expected: {} (or the contents of ./config/config.json if it exists)
```

### 4. Set environment variables for local testing

Create a `.env` file in the project root:

```env
CONTACT_API_URL=https://api.acme-corp.com/v2/contact/submit
APP_BASE_URL=https://app.acme-corp.com
CDN_BASE_URL=https://d1234abcd.cloudfront.net
API_BASE_URL=https://api.acme-corp.com
ADMIN_CONSOLE_URL=https://admin.acme-corp.com
ENV_NAME=local
```

Then restart:
```bash
docker compose up --build
```

### 5. Stop the application

```bash
docker compose down
```

---

## Building the Docker Image Manually

```bash
# From the repository root (build context must be .)
docker build -f Dockerfile -t acme-portal-static:latest .
```

### Run the image locally

```bash
docker run -p 8080:8080 \
  -e CONTACT_API_URL="https://api.acme-corp.com/v2/contact/submit" \
  -e APP_BASE_URL="https://app.acme-corp.com" \
  -e CDN_BASE_URL="https://d1234abcd.cloudfront.net" \
  -e API_BASE_URL="https://api.acme-corp.com" \
  -e ADMIN_CONSOLE_URL="https://admin.acme-corp.com" \
  -e ENV_NAME="production" \
  acme-portal-static:latest
```

---

## Build and Push to Container Registry

### Linux/macOS

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

The script will prompt you to:
1. Enter an image tag (default: `latest`)
2. Select registry type: **1. AWS ECR** or **2. Docker Hub**
3. Provide registry credentials and details

**AWS ECR flow:**
- Prompts for AWS Region, Account ID (auto-detected if blank), and ECR repository name
- Authenticates to ECR using `aws ecr get-login-password`
- Auto-creates the ECR repository if it does not exist
- Builds and pushes the image

**Docker Hub flow:**
- Prompts for Docker Hub username, password/token, and namespace
- Authenticates and pushes the image

---

## AWS ECS Fargate Prerequisites

### 1. IAM Roles

#### ecsTaskExecutionRole
This role is required for ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create the role (if it doesn't exist)
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach the managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### ecsTaskRole (optional)
Required only if the application needs to call AWS APIs (e.g., SSM Parameter Store, S3).

```bash
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach SSM read access (for runtime config injection)
aws iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess
```

### 2. VPC and Networking

Ensure you have:
- A VPC with at least 2 public or private subnets in different Availability Zones
- A security group with inbound rules:
  - TCP port 8080 from the ALB security group (or 0.0.0.0/0 for testing)
  - TCP port 80 on the ALB security group from 0.0.0.0/0

### 3. CloudWatch Log Group

The deploy script creates this automatically, but you can create it manually:

```bash
aws logs create-log-group \
  --log-group-name /ecs/acme-portal-static \
  --region us-east-1
```

---

## ECS Task Definition Explained

The task definition (`ecs/task-definition.json`) configures:

| Field | Value | Notes |
|-------|-------|-------|
| `family` | `acme-portal-static-task` | Task definition family name |
| `requiresCompatibilities` | `["FARGATE"]` | Fargate launch type required |
| `networkMode` | `awsvpc` | Required for Fargate |
| `cpu` | `"512"` | 0.5 vCPU |
| `memory` | `"1024"` | 1 GB RAM |
| `executionRoleArn` | `ecsTaskExecutionRole` | ECR pull + CloudWatch logs |
| `taskRoleArn` | `ecsTaskRole` | Task-level AWS API access |

**Container definition:**
- Image: `{{IMAGE_URI}}` (replaced by deploy script)
- Port: 8080 (TCP)
- Log driver: `awslogs` → `/ecs/acme-portal-static`
- JVM flags: `-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`

**Valid Fargate CPU/Memory combinations:**

| CPU | Valid Memory Options |
|-----|---------------------|
| 256 (.25 vCPU) | 512, 1024, 2048 MB |
| **512 (.5 vCPU)** | **1024**, 2048, 3072, 4096 MB |
| 1024 (1 vCPU) | 2048–8192 MB |
| 2048 (2 vCPU) | 4096–16384 MB |
| 4096 (4 vCPU) | 8192–30720 MB |

---

## ECS Service Configuration

The service definition (`ecs/service-definition.json`) configures:

| Field | Value | Notes |
|-------|-------|-------|
| `serviceName` | `acme-portal-static-service` | ECS service name |
| `launchType` | `FARGATE` | Serverless container compute |
| `desiredCount` | `2` | 2 running tasks for HA |
| `networkMode` | `awsvpc` | Each task gets its own ENI |
| `assignPublicIp` | `ENABLED` | Required for public subnets |
| `maximumPercent` | `200` | Rolling deploy: up to 4 tasks |
| `minimumHealthyPercent` | `50` | At least 1 task always running |

---

## ECS Fargate Deployment Walkthrough

### Step 1: Build and push the image

```bash
./scripts/build-push.sh
# Select: 1 (AWS ECR)
# Enter your AWS region, account ID, and repository name
```

### Step 2: Deploy to ECS Fargate

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- AWS Region (e.g., `us-east-1`)
- ECS Cluster name (auto-created if it doesn't exist)
- ECR Image URI (from Step 1)
- VPC ID
- Subnet IDs (comma-separated, at least 2)
- Security Group ID
- Whether to create an Application Load Balancer

### Step 3: Verify the deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster acme-portal-cluster \
  --services acme-portal-static-service \
  --region us-east-1

# List running tasks
aws ecs list-tasks \
  --cluster acme-portal-cluster \
  --service-name acme-portal-static-service \
  --region us-east-1

# View application logs
aws logs tail /ecs/acme-portal-static --follow --region us-east-1
```

### Step 4: Update the deployment (rolling update)

```bash
# Build and push a new image with a new tag
./scripts/build-push.sh
# Enter tag: v1.1.0

# Re-run deploy script with the new image URI
./scripts/deploy-image.sh
```

---

## Environment Variables Reference

| Variable | Description | Source | Example |
|----------|-------------|--------|---------|
| `JAVA_OPTS` | JVM tuning flags | Task definition | `-Xmx512m -Xms256m ...` |
| `HTML_ROOT` | Directory scanned for HTML files | Task definition | `/app` |
| `CONTACT_API_URL` | Contact form API endpoint | AWS Secrets Manager | `https://api.acme-corp.com/v2/contact/submit` |
| `APP_BASE_URL` | Application base URL (no port) | AWS Secrets Manager | `https://app.acme-corp.com` |
| `CDN_BASE_URL` | CloudFront CDN base URL | AWS SSM Parameter Store | `https://d1234abcd.cloudfront.net` |
| `API_BASE_URL` | Backend API base URL | AWS SSM Parameter Store | `https://api.acme-corp.com` |
| `ADMIN_CONSOLE_URL` | Admin console URL | AWS SSM Parameter Store | `https://admin.acme-corp.com` |
| `ENV_NAME` | Logical environment name | AWS SSM Parameter Store | `production` |

### Injecting secrets from AWS Secrets Manager

In the ECS task definition, add to `containerDefinitions[0].secrets`:

```json
"secrets": [
  {
    "name": "CONTACT_API_URL",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:acme-portal/contact-api-url"
  },
  {
    "name": "APP_BASE_URL",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:acme-portal/app-base-url"
  }
]
```

### Injecting parameters from AWS SSM Parameter Store

```json
"secrets": [
  {
    "name": "CDN_BASE_URL",
    "valueFrom": "arn:aws:ssm:us-east-1:123456789:parameter/acme-portal/cdn-base-url"
  },
  {
    "name": "API_BASE_URL",
    "valueFrom": "arn:aws:ssm:us-east-1:123456789:parameter/acme-portal/api-base-url"
  }
]
```

---

## ECS-Specific Troubleshooting

### Task fails to start (STOPPED state)

```bash
# Get stopped task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster acme-portal-cluster \
  --desired-status STOPPED \
  --region us-east-1 \
  --query "taskArns[0]" --output text)

# Describe the stopped task for stop reason
aws ecs describe-tasks \
  --cluster acme-portal-cluster \
  --tasks "$TASK_ARN" \
  --region us-east-1 \
  --query "tasks[0].{StopCode:stopCode,StopReason:stoppedReason,Containers:containers[*].{Name:name,Reason:reason,ExitCode:exitCode}}"
```

### Common errors and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `CannotPullContainerError` | ECR auth failure or image not found | Verify image URI and ECR permissions on `ecsTaskExecutionRole` |
| `ResourceInitializationError` | Secrets Manager/SSM access denied | Add `secretsmanager:GetSecretValue` or `ssm:GetParameters` to `ecsTaskExecutionRole` |
| `RESOURCE:MEMORY` | Memory limit too low | Increase `memory` in task definition (use valid Fargate combination) |
| `RESOURCE:CPU` | CPU limit too low | Increase `cpu` in task definition |
| `NetworkingError` | Subnet/SG misconfiguration | Verify subnets have route to internet (NAT or IGW) and SG allows outbound |
| Port 8080 not reachable | SG inbound rule missing | Add inbound TCP 8080 rule to the task security group |

### View container logs

```bash
aws logs tail /ecs/acme-portal-static \
  --follow \
  --region us-east-1
```

### Check service events

```bash
aws ecs describe-services \
  --cluster acme-portal-cluster \
  --services acme-portal-static-service \
  --region us-east-1 \
  --query "services[0].events[:10]"
```

---

## ECS Fargate Scaling and Management

### Manual scaling

```bash
aws ecs update-service \
  --cluster acme-portal-cluster \
  --service acme-portal-static-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling (Application Auto Scaling)

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/acme-portal-cluster/acme-portal-static-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create CPU-based scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/acme-portal-cluster/acme-portal-static-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name acme-portal-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

### Blue/Green Deployment with CodeDeploy

For zero-downtime deployments, configure AWS CodeDeploy with ECS:

1. Create a CodeDeploy application and deployment group for ECS
2. Update the ECS service to use `CODE_DEPLOY` deployment controller
3. Use `appspec.yaml` to define the blue/green deployment configuration
4. Trigger deployments via CodePipeline or the CodeDeploy console

---

## Security Considerations

1. **Non-root container user**: The container runs as `appuser` (non-root) for security
2. **No secrets in image**: All environment-specific values are injected at runtime via ECS task definition from AWS Secrets Manager / SSM Parameter Store
3. **No hardcoded URLs**: All API endpoints and CDN URLs use placeholder tokens replaced at container startup
4. **Minimal runtime image**: Uses `mcr.microsoft.com/openjdk/jdk:17-ubuntu` – no unnecessary tools installed
5. **Security group**: Restrict inbound access to port 8080 to the ALB security group only (not 0.0.0.0/0)
6. **ECR image scanning**: Enable ECR image scanning on push to detect vulnerabilities:
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name acme-portal-static \
     --image-scanning-configuration scanOnPush=true \
     --region us-east-1
   ```
7. **VPC endpoints**: Use VPC endpoints for ECR, CloudWatch Logs, and SSM to avoid internet traffic

---

## Java-Specific Notes

### JVM Container Awareness

The application uses these JVM flags for container-aware memory management:
```
-XX:+UseContainerSupport          # Reads cgroup memory limits (Java 10+)
-XX:MaxRAMPercentage=75.0         # Use 75% of container memory for heap
-XX:+UnlockExperimentalVMOptions  # Required for some experimental flags
-Xmx512m -Xms256m                 # Explicit heap bounds (override if needed)
```

With 1024 MB container memory, the JVM heap will be capped at ~768 MB (75%).

### Graceful Shutdown

The JDK `HttpServer` does not natively handle SIGTERM gracefully. For production, consider:
- Adding a JVM shutdown hook in `Application.java` to call `server.stop(5)` (5-second grace period)
- Setting `stopTimeout` in the ECS service to allow in-flight requests to complete

### Timezone

The JVM timezone is set to UTC via `-Duser.timezone=UTC` in `JAVA_OPTS`. Override with:
```
-Duser.timezone=America/New_York
```

### Charset

UTF-8 encoding is enforced via `-Dfile.encoding=UTF-8` in `JAVA_OPTS`.

---

## AWS CodeBuild Integration

The project includes a `buildspec.yml` for AWS CodeBuild that:
1. Installs `html-minifier-terser` for HTML minification (cz-html-1009)
2. Runs `mvn clean package -DskipTests`
3. Minifies all HTML files before building the Docker image
4. Validates image size against a configurable limit (default: 150 MB)
5. Pushes the image to ECR and writes `imagedefinitions.json` for CodePipeline

To use with CodePipeline, connect your repository and create a pipeline with:
- Source: GitHub/CodeCommit
- Build: CodeBuild (using `buildspec.yml`)
- Deploy: ECS (using `imagedefinitions.json`)
