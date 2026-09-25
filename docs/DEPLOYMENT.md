# Deployment Guide – acme-portal-static (JAVAHTMLMONO)

## Overview

This guide covers building, pushing, and deploying the **acme-portal-static** Java application to **AWS ECS Fargate**.

The application is a lightweight Java HTTP server (JDK built-in `com.sun.net.httpserver`) that:
- Serves static HTML pages with server-side environment variable injection
- Exposes a health check endpoint at `GET /api/health`
- Listens on port **8080**
- Injects runtime configuration (CDN URLs, API endpoints) from AWS Secrets Manager / SSM Parameter Store

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Local Development with Docker Compose](#local-development-with-docker-compose)
4. [Build and Push Docker Image](#build-and-push-docker-image)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [ECS Task Definition Explained](#ecs-task-definition-explained)
7. [ECS Service Configuration](#ecs-service-configuration)
8. [ECS Fargate Deployment Walkthrough](#ecs-fargate-deployment-walkthrough)
9. [Environment Variables Reference](#environment-variables-reference)
10. [ECS-Specific Troubleshooting](#ecs-specific-troubleshooting)
11. [ECS Fargate Scaling and Management](#ecs-fargate-scaling-and-management)
12. [Security Considerations](#security-considerations)
13. [Technology-Specific Notes](#technology-specific-notes)

---

## Prerequisites

### Local Development
- **Docker** 24.x or later
- **Docker Compose** v2.x or later
- **Java 17** (Eclipse Temurin recommended)
- **Maven 3.9.x**

### AWS Deployment
- **AWS CLI** v2.x configured with appropriate credentials
- **AWS Account** with permissions for:
  - ECS (create clusters, services, task definitions)
  - ECR (create repositories, push images)
  - IAM (create/assign roles)
  - CloudWatch Logs (create log groups)
  - EC2 (VPC, subnets, security groups)
  - Secrets Manager / SSM Parameter Store (store secrets)
  - Elastic Load Balancing (optional, for ALB)

---

## Project Structure

```
JAVAHTMLMONO/
├── Dockerfile                    # Multi-stage build (Maven builder + Temurin 17 JDK runtime)
├── docker-compose.yml            # Local development compose file
├── .dockerignore                 # Excludes build artifacts, wrapper files, dev HTML
├── docker-entrypoint.sh          # Startup script: path normalisation + env var substitution
├── pom.xml                       # Maven build descriptor (Java 17, JAR packaging)
├── src/
│   └── main/java/com/trianz/acmeportal/
│       ├── Application.java      # Main class – JDK HttpServer on port 8080
│       └── HealthHandler.java    # GET /api/health → {"status":"ok"}
├── pages/
│   └── dashboard.html            # Dashboard page with runtime config injection
├── forms/
│   └── contact.html              # Contact form with CONTACT_API_URL injection
├── partials/                     # HTML partials
├── app/                          # SPA shell HTML
├── assets/                       # CSS and JS assets
├── index.html                    # Root index page
├── ecs/
│   ├── task-definition.json      # ECS Fargate task definition
│   └── service-definition.json   # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS: build and push to ECR or Docker Hub
│   ├── build-push.bat            # Windows: build and push to ECR or Docker Hub
│   ├── deploy-image.sh           # Linux/macOS: deploy to AWS ECS Fargate
│   └── deploy-image.bat          # Windows: deploy to AWS ECS Fargate
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development with Docker Compose

### 1. Create a local `.env` file

```bash
cat > .env <<EOF
CONTACT_API_URL=http://localhost:9000
TELEMETRY_BASE_URL=http://localhost:5000
CDN_BASE_URL=http://localhost:8081
STATIC_ASSETS_BASE_URL=http://localhost:8081/static
API_BASE_URL=http://localhost:9000/api
TIMESTAMP_RENDER_MODE=client
EOF
```

### 2. Build and start the application

```bash
docker compose up --build
```

### 3. Verify the application

```bash
# Health check
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}

# Dashboard page
curl http://localhost:8080/pages/dashboard.html

# Contact form
curl http://localhost:8080/forms/contact.html
```

### 4. Stop the application

```bash
docker compose down
```

---

## Build and Push Docker Image

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
1. Enter an image tag (default: `latest`)
2. Select registry type: **AWS ECR** or **Docker Hub**
3. Provide registry credentials and details

**ECR flow:**
- Authenticates via `aws ecr get-login-password`
- Auto-creates the ECR repository if it does not exist
- Builds and pushes the image

**Docker Hub flow:**
- Authenticates via `docker login`
- Builds and pushes the image

---

## AWS ECS Fargate Prerequisites

### 1. IAM Roles

#### ECS Task Execution Role
Required for ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create the execution role
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

# Add Secrets Manager and SSM access (required for secrets injection)
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess
```

#### ECS Task Role (optional)
For application-level AWS API access (e.g., S3, DynamoDB).

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
```

### 2. VPC and Networking

Ensure you have:
- A **VPC** with DNS resolution enabled
- At least **2 public or private subnets** in different Availability Zones
- A **Security Group** allowing:
  - Inbound TCP port **8080** from the ALB security group (or `0.0.0.0/0` for testing)
  - Outbound all traffic (for ECR image pulls and Secrets Manager access)

```bash
# Example: Create security group
aws ec2 create-security-group \
  --group-name acme-portal-sg \
  --description "Security group for acme-portal-static ECS tasks" \
  --vpc-id vpc-XXXXXXXX

# Allow inbound on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXXXX \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

### 3. AWS Secrets Manager / SSM Parameter Store

Store runtime secrets before deploying:

```bash
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Secrets Manager secrets
aws secretsmanager create-secret \
  --name "acme-portal/CONTACT_API_URL" \
  --secret-string "https://api.acme-corp.com" \
  --region "${AWS_REGION}"

aws secretsmanager create-secret \
  --name "acme-portal/TELEMETRY_BASE_URL" \
  --secret-string "https://telemetry.acme-corp.com" \
  --region "${AWS_REGION}"

aws secretsmanager create-secret \
  --name "acme-portal/CDN_BASE_URL" \
  --secret-string "https://d1234abcd.cloudfront.net" \
  --region "${AWS_REGION}"

# SSM Parameter Store parameters
aws ssm put-parameter \
  --name "/acme-portal/STATIC_ASSETS_BASE_URL" \
  --value "https://static.acme-corp.com" \
  --type "SecureString" \
  --region "${AWS_REGION}"

aws ssm put-parameter \
  --name "/acme-portal/API_BASE_URL" \
  --value "https://api.acme-corp.com" \
  --type "SecureString" \
  --region "${AWS_REGION}"
```

### 4. CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name "/ecs/acme-portal-static" \
  --region us-east-1

# Set retention policy (optional)
aws logs put-retention-policy \
  --log-group-name "/ecs/acme-portal-static" \
  --retention-in-days 30 \
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
| `executionRoleArn` | `ecsTaskExecutionRole` | Allows ECR pull + CloudWatch logs |
| `taskRoleArn` | `ecsTaskRole` | Application-level AWS API access |

### Container Definition

| Field | Value | Notes |
|-------|-------|-------|
| `name` | `acme-portal-static` | Container name |
| `image` | `{{IMAGE_URI}}` | Replaced by deploy script |
| `containerPort` | `8080` | Application port |
| `logDriver` | `awslogs` | CloudWatch Logs |
| `logGroup` | `/ecs/acme-portal-static` | CloudWatch log group |

### Valid Fargate CPU/Memory Combinations

| CPU | Memory Options |
|-----|---------------|
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
| `launchType` | `FARGATE` | Serverless containers |
| `desiredCount` | `2` | 2 tasks for high availability |
| `assignPublicIp` | `ENABLED` | Required for public subnet tasks |
| `maximumPercent` | `200` | Rolling deployment |
| `minimumHealthyPercent` | `50` | Allows 1 task to be replaced at a time |

---

## ECS Fargate Deployment Walkthrough

### Step 1: Build and push the Docker image

```bash
./scripts/build-push.sh
# Note the full image URI output (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest)
```

### Step 2: Run the deployment script

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- AWS Region
- ECS Cluster name
- ECR Image URI
- VPC ID
- Subnet IDs (comma-separated)
- Security Group ID
- Whether to create an Application Load Balancer

### Step 3: Verify the deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster acme-portal-cluster \
  --services acme-portal-static-service \
  --region us-east-1

# View running tasks
aws ecs list-tasks \
  --cluster acme-portal-cluster \
  --service-name acme-portal-static-service \
  --region us-east-1

# Tail CloudWatch logs
aws logs tail /ecs/acme-portal-static --follow --region us-east-1
```

### Step 4: Test the health endpoint

```bash
# If using ALB:
curl http://<ALB_DNS_NAME>/api/health

# If using direct task IP (for testing):
TASK_ARN=$(aws ecs list-tasks --cluster acme-portal-cluster --service-name acme-portal-static-service --query "taskArns[0]" --output text --region us-east-1)
TASK_IP=$(aws ecs describe-tasks --cluster acme-portal-cluster --tasks $TASK_ARN --region us-east-1 --query "tasks[0].attachments[0].details[?name=='privateIPv4Address'].value" --output text)
curl http://${TASK_IP}:8080/api/health
```

---

## Environment Variables Reference

| Variable | Source | Description |
|----------|--------|-------------|
| `JAVA_OPTS` | Task definition | JVM memory and GC settings |
| `HTML_ROOT` | Task definition | HTML root directory for entrypoint script |
| `TZ` | Task definition | Timezone (UTC) |
| `TIMESTAMP_RENDER_MODE` | Task definition | Controls timestamp rendering (`client`) |
| `CONTACT_API_URL` | Secrets Manager | Base URL for contact form submission API |
| `TELEMETRY_BASE_URL` | Secrets Manager | Telemetry service base URL (replaces hardcoded :5000) |
| `CDN_BASE_URL` | Secrets Manager | CloudFront CDN base URL for static assets |
| `STATIC_ASSETS_BASE_URL` | SSM Parameter Store | Static assets origin URL |
| `API_BASE_URL` | SSM Parameter Store | Backend API base URL |

---

## ECS-Specific Troubleshooting

### Task fails to start

```bash
# Check stopped task reason
aws ecs describe-tasks \
  --cluster acme-portal-cluster \
  --tasks <TASK_ARN> \
  --region us-east-1 \
  --query "tasks[0].{Status:lastStatus,StopCode:stopCode,StopReason:stoppedReason}"
```

**Common causes:**
- `CannotPullContainerError`: ECR authentication issue or missing `executionRoleArn`
- `ResourceInitializationError`: Secrets Manager/SSM access denied – check execution role permissions
- `OutOfMemoryError`: Increase task memory (use valid Fargate CPU/memory combination)

### Container exits immediately

```bash
# View CloudWatch logs
aws logs get-log-events \
  --log-group-name /ecs/acme-portal-static \
  --log-stream-name "ecs/acme-portal-static/<TASK_ID>" \
  --region us-east-1
```

### Network connectivity issues

- Verify security group allows inbound TCP 8080
- For private subnets: ensure NAT Gateway exists for ECR/Secrets Manager access
- For public subnets: ensure `assignPublicIp: ENABLED`
- Check VPC endpoint for ECR if using private subnets without NAT

### Health check failures

The application health endpoint is `GET /api/health` returning `{"status":"ok"}`.

```bash
# Test from within the VPC
curl -v http://<TASK_PRIVATE_IP>:8080/api/health
```

### Invalid CPU/Memory combination

Ensure task definition uses valid Fargate combinations:
- Default: `cpu: "512"`, `memory: "1024"` ✅
- Invalid: `cpu: "512"`, `memory: "512"` ❌

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

### Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/acme-portal-cluster/acme-portal-static-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1

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
  }' \
  --region us-east-1
```

### Blue/Green Deployment with CodeDeploy

For zero-downtime deployments, configure AWS CodeDeploy with ECS:

1. Create a CodeDeploy application and deployment group targeting the ECS service
2. Use `deploymentController: CODE_DEPLOY` in the service definition
3. Configure two target groups (blue and green) on the ALB
4. Trigger deployments via CodeDeploy with the new task definition ARN

### Force new deployment (rolling update)

```bash
aws ecs update-service \
  --cluster acme-portal-cluster \
  --service acme-portal-static-service \
  --force-new-deployment \
  --region us-east-1
```

---

## Security Considerations

1. **Non-root container user**: The Dockerfile creates and uses `appuser` (non-root) for all runtime operations.

2. **Secrets management**: All sensitive configuration (API URLs, CDN URLs) is injected at runtime from AWS Secrets Manager and SSM Parameter Store – never baked into the container image.

3. **Image scanning**: Enable ECR image scanning on push:
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name acme-portal-static \
     --image-scanning-configuration scanOnPush=true \
     --region us-east-1
   ```

4. **Least privilege IAM**: Scope the `ecsTaskRole` to only the AWS services the application actually needs.

5. **Security group**: Restrict inbound access to port 8080 to the ALB security group only (not `0.0.0.0/0`) in production.

6. **VPC isolation**: Deploy tasks in private subnets with a NAT Gateway for outbound internet access.

7. **No development files in production**: `test.html`, `build-info.html`, and source maps are excluded from the container image via `.dockerignore`.

---

## Technology-Specific Notes

### Java / JVM Configuration

The application uses the JDK built-in `com.sun.net.httpserver.HttpServer` – no external web framework dependencies.

**JVM flags used:**
```
-Xmx512m                    # Maximum heap size
-Xms256m                    # Initial heap size
-XX:+UseContainerSupport    # Enables JVM container awareness (Java 10+)
-XX:MaxRAMPercentage=75.0   # Use 75% of container memory for heap
-XX:+ExitOnOutOfMemoryError # Crash fast on OOM (let ECS restart the task)
-Djava.security.egd=file:/dev/./urandom  # Faster SecureRandom on Linux
```

### Maven Build

- Build tool: **Maven 3.9.4** (system `mvn`, never wrapper)
- Java version: **17** (Eclipse Temurin)
- Packaging: **JAR** with embedded main class
- Artifact: `target/acme-portal-static.jar`
- Build command: `mvn clean package -DskipTests`

### Health Check Endpoint

- **Path**: `GET /api/health`
- **Response**: `{"status":"ok"}` (HTTP 200)
- **Implementation**: `HealthHandler.java`
- **ECS health check**: Handled by ALB target group health checks (path: `/api/health`)

### Runtime Configuration Injection

The `docker-entrypoint.sh` script performs the following at container startup:
1. Normalises Windows backslash path separators in HTML files (`cz-html-1002`)
2. Substitutes `${CDN_BASE_URL}` placeholder in HTML files (`cz-html-1008`)
3. Substitutes `${TELEMETRY_BASE_URL}` placeholder in HTML files (`cz-html-1007`)
4. Substitutes `${STATIC_ASSETS_BASE_URL}` and `${API_BASE_URL}` placeholders (`cz-html-1011`)
5. Hands off to `java -jar /app/app.jar`

The Java `Application.java` additionally injects `window.__ENV__` into HTML responses at request time for `CONTACT_API_URL`, `TIMESTAMP_RENDER_MODE`, `STATIC_ASSETS_BASE_URL`, and `API_BASE_URL`.
