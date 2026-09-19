# acme-portal-static — AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development with Docker Compose](#local-development-with-docker-compose)
5. [Build and Push Docker Image](#build-and-push-docker-image)
6. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
7. [ECS Task Definition Explained](#ecs-task-definition-explained)
8. [ECS Service Configuration](#ecs-service-configuration)
9. [ECS Fargate Deployment Walkthrough](#ecs-fargate-deployment-walkthrough)
10. [ECS-Specific Troubleshooting](#ecs-specific-troubleshooting)
11. [ECS Fargate Scaling and Management](#ecs-fargate-scaling-and-management)
12. [Configuration Management](#configuration-management)
13. [Security Considerations](#security-considerations)
14. [Java-Specific Notes](#java-specific-notes)

---

## Overview

**Application**: acme-portal-static  
**Technology**: Java 17, plain JDK `com.sun.net.httpserver.HttpServer` (no Spring Boot)  
**Build Tool**: Apache Maven 3.x  
**Package**: Executable JAR (`acme-portal-static.jar`)  
**Application Port**: `8080`  
**Health Endpoint**: `GET /api/health` → `{"status":"ok"}`  
**Target Platform**: AWS ECS Fargate  

The application is a minimal Java HTTP server that serves static HTML assets and exposes a health endpoint. It uses only built-in JDK APIs and has no external runtime dependencies.

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Docker Desktop | 24.x+ | Build and run containers |
| Docker Compose | v2.x+ | Local multi-container orchestration |
| Java JDK | 17+ | Local build (optional — Docker handles it) |
| Apache Maven | 3.9.x+ | Local build (optional — Docker handles it) |

### AWS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | Interact with AWS services |
| Docker | 24.x+ | Build and push images |
| Python 3 | 3.8+ | Used by deploy-image.sh for JSON manipulation |

---

## Project Structure

```
Aws-fargate/
├── src/main/java/com/trianz/acmeportal/
│   ├── Application.java          # Main class — starts HttpServer on :8080
│   └── HealthHandler.java        # GET /api/health handler
├── assets/                       # CSS, JS static assets
├── app/                          # SPA HTML pages
├── pages/                        # Dashboard pages
├── forms/                        # Form pages
├── partials/                     # Partial HTML templates
├── index.html                    # Root HTML page
├── pom.xml                       # Maven build descriptor
├── Dockerfile                    # Multi-stage Docker build
├── docker-compose.yml            # Local development compose file
├── .dockerignore                 # Docker build exclusions
├── ecs/
│   ├── task-definition.json      # ECS Fargate task definition
│   └── service-definition.json   # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS build & push script
│   ├── build-push.bat            # Windows build & push script
│   ├── deploy-image.sh           # Linux/macOS ECS deploy script
│   └── deploy-image.bat          # Windows ECS deploy script
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development with Docker Compose

### 1. Build and Start

```bash
# From repository root
docker compose up --build
```

### 2. Verify the Application

```bash
# Health check
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}

# Static frontend
open http://localhost:8080
```

### 3. View Logs

```bash
docker compose logs -f acme-portal-static
```

### 4. Stop

```bash
docker compose down
```

### Environment Variables (docker-compose.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_OPTS` | `-Xms128m -Xmx384m ...` | JVM tuning flags |
| `TZ` | `UTC` | Container timezone |

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

### What the Script Does

1. Prompts for registry type: **AWS ECR** or **Docker Hub**
2. Prompts for image tag (defaults to `latest`)
3. Sanitizes the image name to lowercase with hyphens
4. Authenticates with the selected registry
5. For ECR: auto-creates the repository if it doesn't exist
6. Builds the Docker image using the `Dockerfile` at the project root
7. Pushes the image to the registry

### Manual Build (ECR Example)

```bash
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
ECR_REPO=acme-portal-static
IMAGE_TAG=1.0.0

# Authenticate
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repo (if needed)
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# Build & push
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG} .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
```

---

## AWS ECS Fargate Prerequisites

### 1. AWS CLI Configuration

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, Region, Output format
```

### 2. VPC and Networking

- **VPC**: A VPC with at least 2 subnets in different Availability Zones
- **Subnets**: Public subnets (for `assignPublicIp: ENABLED`) or private subnets with NAT Gateway
- **Security Group**: Must allow:
  - **Inbound**: TCP port `8080` from ALB security group (or `0.0.0.0/0` for testing)
  - **Outbound**: All traffic (for ECR image pulls and CloudWatch logs)

```bash
# Example: Create a security group
aws ec2 create-security-group \
  --group-name acme-portal-static-sg \
  --description "Security group for acme-portal-static ECS tasks" \
  --vpc-id vpc-xxxxxxxx

# Allow inbound on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

### 3. IAM Roles

#### ECS Task Execution Role (`ecsTaskExecutionRole`)
Required for ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create the role
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

#### ECS Task Role (`ecsTaskRole`)
Optional — grants the running container permissions to call AWS services.

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

### 4. CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/acme-portal-static \
  --region us-east-1
```

---

## ECS Task Definition Explained

File: `ecs/task-definition.json`

| Field | Value | Notes |
|-------|-------|-------|
| `family` | `acme-portal-static-task` | Task definition family name |
| `requiresCompatibilities` | `["FARGATE"]` | Fargate launch type |
| `networkMode` | `awsvpc` | Required for Fargate |
| `cpu` | `"512"` | 0.5 vCPU |
| `memory` | `"1024"` | 1 GB RAM |
| `executionRoleArn` | `ecsTaskExecutionRole` | ECR pull + CloudWatch logs |
| `taskRoleArn` | `ecsTaskRole` | Task-level AWS permissions |

### Valid Fargate CPU/Memory Combinations

| CPU | Memory Options |
|-----|---------------|
| 256 (.25 vCPU) | 512, 1024, 2048 MB |
| **512 (.5 vCPU)** | **1024**, 2048, 3072, 4096 MB |
| 1024 (1 vCPU) | 2048–8192 MB |
| 2048 (2 vCPU) | 4096–16384 MB |
| 4096 (4 vCPU) | 8192–30720 MB |

### Container Definition

```json
{
  "name": "acme-portal-static",
  "image": "{{IMAGE_URI}}",
  "essential": true,
  "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
  "environment": [
    {"name": "JAVA_OPTS", "value": "-Xms128m -Xmx384m ..."},
    {"name": "TZ", "value": "UTC"}
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/acme-portal-static",
      "awslogs-region": "{{AWS_REGION}}",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

---

## ECS Service Configuration

File: `ecs/service-definition.json`

| Field | Value | Notes |
|-------|-------|-------|
| `serviceName` | `acme-portal-static-service` | ECS service name |
| `launchType` | `FARGATE` | Serverless compute |
| `desiredCount` | `2` | Number of running tasks |
| `networkMode` | `awsvpc` | Each task gets its own ENI |
| `assignPublicIp` | `ENABLED` | Required for public subnet access |

### Deployment Configuration

```json
{
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50
  }
}
```

This allows rolling updates: ECS can run up to 4 tasks (200% of 2) during deployment and must keep at least 1 task (50% of 2) healthy.

---

## ECS Fargate Deployment Walkthrough

### Step 1: Push Image to ECR

```bash
./scripts/build-push.sh
# Select: 1 (AWS ECR)
# Enter region, account ID, repo name, tag
```

### Step 2: Run Deployment Script

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- AWS Region
- ECS Cluster name
- ECR Image URI
- Subnet IDs (2 required)
- Security Group ID
- Whether to create an Application Load Balancer

### Step 3: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster acme-portal-static-cluster \
  --services acme-portal-static-service \
  --region us-east-1

# List running tasks
aws ecs list-tasks \
  --cluster acme-portal-static-cluster \
  --service-name acme-portal-static-service \
  --region us-east-1

# View application logs
aws logs tail /ecs/acme-portal-static --follow --region us-east-1
```

### Step 4: Test the Application

```bash
# If using ALB (DNS provided by deploy script):
curl http://<ALB_DNS>/api/health

# If using direct task IP (find from ECS console or CLI):
TASK_ARN=$(aws ecs list-tasks --cluster acme-portal-static-cluster \
  --service-name acme-portal-static-service --query "taskArns[0]" --output text)
TASK_IP=$(aws ecs describe-tasks --cluster acme-portal-static-cluster \
  --tasks $TASK_ARN --query "tasks[0].attachments[0].details[?name=='privateIPv4Address'].value" \
  --output text)
curl http://${TASK_IP}:8080/api/health
```

---

## ECS-Specific Troubleshooting

### Task Fails to Start

```bash
# Check stopped task reason
aws ecs describe-tasks \
  --cluster acme-portal-static-cluster \
  --tasks <TASK_ARN> \
  --query "tasks[0].stoppedReason"

# Check container exit code
aws ecs describe-tasks \
  --cluster acme-portal-static-cluster \
  --tasks <TASK_ARN> \
  --query "tasks[0].containers[0].{ExitCode:exitCode,Reason:reason}"
```

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `CannotPullContainerError` | ECR auth failure or wrong image URI | Verify `executionRoleArn` has ECR permissions; check image URI |
| `ResourceInitializationError` | Network issue pulling image | Ensure subnets have internet access (public IP or NAT) |
| `OutOfMemoryError` in logs | JVM heap too large for container | Reduce `-Xmx` or increase task memory |
| `STOPPED (Essential container exited)` | Application crash | Check CloudWatch logs for stack trace |
| Invalid CPU/memory combination | Wrong Fargate values | Use valid combinations (e.g., cpu:512, memory:1024) |

### View CloudWatch Logs

```bash
# Stream logs in real-time
aws logs tail /ecs/acme-portal-static --follow --region us-east-1

# Get last 100 log events
aws logs get-log-events \
  --log-group-name /ecs/acme-portal-static \
  --log-stream-name ecs/acme-portal-static/<TASK_ID> \
  --limit 100 \
  --region us-east-1
```

### Network Connectivity Issues

```bash
# Verify security group allows port 8080
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx \
  --query "SecurityGroups[0].IpPermissions"

# Check subnet route table has internet gateway (for public subnets)
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxxxxx"
```

---

## ECS Fargate Scaling and Management

### Manual Scaling

```bash
# Scale to 4 tasks
aws ecs update-service \
  --cluster acme-portal-static-cluster \
  --service acme-portal-static-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/acme-portal-static-cluster/acme-portal-static-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 1 \
  --max-capacity 10

# Create CPU-based scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/acme-portal-static-cluster/acme-portal-static-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name acme-portal-static-cpu-scaling \
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
2. Configure two target groups (blue and green) on the ALB
3. Use `deploymentController: CODE_DEPLOY` in the service definition
4. Trigger deployments via CodeDeploy instead of `update-service`

### Force New Deployment (Rolling Update)

```bash
aws ecs update-service \
  --cluster acme-portal-static-cluster \
  --service acme-portal-static-service \
  --force-new-deployment \
  --region us-east-1
```

---

## Configuration Management

### Environment Variables

Override environment variables at deployment time by modifying `ecs/task-definition.json` before registering:

```json
"environment": [
  {"name": "JAVA_OPTS", "value": "-Xms256m -Xmx768m -XX:+UseContainerSupport"},
  {"name": "TZ", "value": "America/New_York"}
]
```

### AWS Secrets Manager Integration

For sensitive configuration, use AWS Secrets Manager with ECS secrets:

```json
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:acme-portal/db-password"
  }
]
```

Grant the `ecsTaskExecutionRole` permission to read secrets:

```bash
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

---

## Security Considerations

1. **Non-root container user**: The Dockerfile creates and uses `appuser` (non-root) for all runtime operations.

2. **Minimal runtime image**: Uses `eclipse-temurin:17-jdk` — no unnecessary tools installed. No `curl`, `wget`, or package managers in the runtime stage.

3. **No sensitive data in image**: All secrets and credentials are injected via environment variables or AWS Secrets Manager at runtime.

4. **Security Group least privilege**: Restrict inbound traffic to only port `8080` from the ALB security group, not `0.0.0.0/0`.

5. **ECR image scanning**: Enable ECR image scanning on push:
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name acme-portal-static \
     --image-scanning-configuration scanOnPush=true
   ```

6. **ECR Lifecycle Policy**: Apply the included `ecr-lifecycle-policy.json` to expire dev-tagged images:
   ```bash
   aws ecr put-lifecycle-policy \
     --repository-name acme-portal-static \
     --lifecycle-policy-text file://ecr-lifecycle-policy.json
   ```

7. **VPC isolation**: Deploy tasks in private subnets with a NAT Gateway for production workloads.

8. **IAM least privilege**: Scope `ecsTaskRole` permissions to only the AWS services the application actually needs.

---

## Java-Specific Notes

### JVM Container Awareness

The Dockerfile sets these JVM flags for optimal container behavior:

```
-XX:+UseContainerSupport      # JVM reads cgroup limits (Java 10+)
-XX:MaxRAMPercentage=75.0     # Use 75% of container memory for heap
-XX:+UseG1GC                  # G1 garbage collector (good for containers)
-Xms128m -Xmx384m             # Explicit heap bounds (overrides MaxRAMPercentage)
```

With 1024 MB Fargate task memory:
- JVM heap: up to 384 MB
- Non-heap (metaspace, threads, etc.): ~200–300 MB
- OS overhead: ~100 MB
- Total: well within 1024 MB

### Startup Time

This application uses the built-in JDK `HttpServer` (no Spring Boot), so startup is very fast (< 1 second). No `startPeriod` grace period is needed for health checks.

### Graceful Shutdown

The Dockerfile sets `STOPSIGNAL SIGTERM`. ECS sends `SIGTERM` before `SIGKILL` (default 30-second grace period). The JDK `HttpServer` will stop accepting new connections and finish in-flight requests.

To extend the grace period:
```json
"stopTimeout": 60
```
Add this to the container definition in `task-definition.json`.

### Logging

Logs are sent to CloudWatch via the `awslogs` driver. The log group `/ecs/acme-portal-static` is created automatically by the deploy script. Each task creates a log stream named `ecs/acme-portal-static/<TASK_ID>`.

To add structured JSON logging, consider adding SLF4J + Logback to the project dependencies and configuring a JSON encoder.
