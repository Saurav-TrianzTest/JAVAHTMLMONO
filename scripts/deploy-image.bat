@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat – acme-portal-static (JAVAHTMLMONO)
REM Deploy to AWS ECS Fargate
REM Usage: scripts\deploy-image.bat
REM Run from repository root directory
REM =============================================================================

set "SERVICE_NAME=acme-portal-static-service"
set "TASK_FAMILY=acme-portal-static-task"
set "CONTAINER_NAME=acme-portal-static"
set "LOG_GROUP=/ecs/acme-portal-static"
set "TASK_DEF_FILE=ecs\task-definition.json"
set "SERVICE_DEF_FILE=ecs\service-definition.json"

echo ==============================================
echo   acme-portal-static - ECS Fargate Deploy
echo ==============================================
echo.

REM ── Gather configuration ──────────────────────────────────────────────────────
set /p "AWS_REGION=AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "CLUSTER_NAME=ECS Cluster name [acme-portal-cluster]: "
if "!CLUSTER_NAME!"=="" set "CLUSTER_NAME=acme-portal-cluster"

set /p "IMAGE_URI=ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI is required.
    exit /b 1
)

echo.
echo -- Network Configuration --------------------------------------------------
set /p "VPC_ID=VPC ID (e.g. vpc-0abc12345): "
if "!VPC_ID!"=="" (
    echo ERROR: VPC ID is required.
    exit /b 1
)

set /p "SUBNETS_RAW=Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): "
if "!SUBNETS_RAW!"=="" (
    echo ERROR: At least one subnet ID is required.
    exit /b 1
)

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_RAW!") do (
    set "SUBNET_1=%%a"
    set "SUBNET_2=%%b"
)
if "!SUBNET_2!"=="" set "SUBNET_2=!SUBNET_1!"

set /p "SECURITY_GROUP=Security Group ID (e.g. sg-0abc12345): "
if "!SECURITY_GROUP!"=="" (
    echo ERROR: Security Group ID is required.
    exit /b 1
)

REM ── Get AWS Account ID ────────────────────────────────────────────────────────
echo.
echo Fetching AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text 2^>^&1') do set "ACCOUNT_ID=%%i"
echo Account ID    : !ACCOUNT_ID!

REM ── Create CloudWatch log group ───────────────────────────────────────────────
echo.
echo Ensuring CloudWatch log group '!LOG_GROUP!' exists...
aws logs create-log-group --log-group-name "!LOG_GROUP!" --region "!AWS_REGION!" >nul 2>&1
echo Log group ready.

REM ── Check / create ECS cluster ───────────────────────────────────────────────
echo.
echo Checking ECS cluster '!CLUSTER_NAME!'...
for /f "delims=" %%i in ('aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" --query "clusters[0].status" --output text 2^>^&1') do set "CLUSTER_STATUS=%%i"

if not "!CLUSTER_STATUS!"=="ACTIVE" (
    echo Creating ECS cluster '!CLUSTER_NAME!'...
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!"
    echo Cluster created.
) else (
    echo Cluster '!CLUSTER_NAME!' is ACTIVE.
)

REM ── Load balancer prompt ──────────────────────────────────────────────────────
echo.
set /p "NEED_LB=Do you need an Application Load Balancer for this service? (y/n) [n]: "
if "!NEED_LB!"=="" set "NEED_LB=n"

set "TARGET_GROUP_ARN="
set "ALB_DNS="

if /i "!NEED_LB!"=="y" (
    echo.
    echo -- Creating Application Load Balancer -------------------------------------
    set "ALB_NAME=acme-portal-static-alb"
    set "TG_NAME=acme-portal-static-tg"

    echo Creating ALB '!ALB_NAME!'...
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name "!ALB_NAME!" --subnets "!SUBNET_1!" "!SUBNET_2!" --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>^&1') do set "ALB_ARN=%%i"
    echo ALB ARN: !ALB_ARN!

    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns "!ALB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text 2^>^&1') do set "ALB_DNS=%%i"

    echo Creating Target Group '!TG_NAME!'...
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 8080 --vpc-id "!VPC_ID!" --target-type ip --health-check-path "/api/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text 2^>^&1') do set "TARGET_GROUP_ARN=%%i"
    echo Target Group ARN: !TARGET_GROUP_ARN!

    echo Creating ALB listener on port 80...
    aws elbv2 create-listener --load-balancer-arn "!ALB_ARN!" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=!TARGET_GROUP_ARN!" --region "!AWS_REGION!" >nul
    echo ALB listener created.
)

REM ── Prepare task definition JSON ──────────────────────────────────────────────
echo.
echo Preparing task definition...
set "TASK_DEF_TMP=%TEMP%\task-definition-deploy.json"
copy /y "%TASK_DEF_FILE%" "%TASK_DEF_TMP%" >nul

powershell -NoProfile -Command ^
  "(Get-Content '%TASK_DEF_TMP%') -replace '\{\{IMAGE_URI\}\}','!IMAGE_URI!' -replace '\{\{AWS_REGION\}\}','!AWS_REGION!' -replace '\{\{ACCOUNT_ID\}\}','!ACCOUNT_ID!' | Set-Content '%TASK_DEF_TMP%'"

REM ── Register task definition ──────────────────────────────────────────────────
echo Registering ECS task definition '!TASK_FAMILY!'...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json "file://%TASK_DEF_TMP%" --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text 2^>^&1') do set "TASK_DEF_ARN=%%i"
echo Task definition ARN: !TASK_DEF_ARN!
del /f /q "%TASK_DEF_TMP%" >nul 2>&1

REM ── Prepare service definition JSON ──────────────────────────────────────────
echo.
echo Preparing service definition...
set "SERVICE_DEF_TMP=%TEMP%\service-definition-deploy.json"
copy /y "%SERVICE_DEF_FILE%" "%SERVICE_DEF_TMP%" >nul

powershell -NoProfile -Command ^
  "(Get-Content '%SERVICE_DEF_TMP%') -replace '\{\{CLUSTER_NAME\}\}','!CLUSTER_NAME!' -replace '\{\{SUBNET_1\}\}','!SUBNET_1!' -replace '\{\{SUBNET_2\}\}','!SUBNET_2!' -replace '\{\{SECURITY_GROUP\}\}','!SECURITY_GROUP!' | Set-Content '%SERVICE_DEF_TMP%'"

REM ── Inject load balancer if needed ───────────────────────────────────────────
if /i "!NEED_LB!"=="y" (
    powershell -NoProfile -Command ^
      "$svc = Get-Content '%SERVICE_DEF_TMP%' | ConvertFrom-Json; $lb = @{targetGroupArn='!TARGET_GROUP_ARN!'; containerName='!CONTAINER_NAME!'; containerPort=8080}; $svc | Add-Member -NotePropertyName 'loadBalancers' -NotePropertyValue @($lb) -Force; $svc | Add-Member -NotePropertyName 'healthCheckGracePeriodSeconds' -NotePropertyValue 300 -Force; $svc | ConvertTo-Json -Depth 10 | Set-Content '%SERVICE_DEF_TMP%'"
    echo Load balancer configuration injected into service definition.
)

REM ── Create or update ECS service ──────────────────────────────────────────────
echo.
echo Checking if ECS service '!SERVICE_NAME!' exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[?status!=''INACTIVE''].serviceName" --output text 2^>^&1') do set "EXISTING_SERVICE=%%i"

if "!EXISTING_SERVICE!"=="" (
    echo Creating new ECS service '!SERVICE_NAME!'...
    aws ecs create-service --cli-input-json "file://%SERVICE_DEF_TMP%" --region "!AWS_REGION!"
    echo Service created.
) else (
    echo Updating existing ECS service '!SERVICE_NAME!'...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "!SERVICE_NAME!" --task-definition "!TASK_DEF_ARN!" --region "!AWS_REGION!" >nul
    echo Service updated.
)

del /f /q "%SERVICE_DEF_TMP%" >nul 2>&1

REM ── Wait for service stability ────────────────────────────────────────────────
echo.
echo Waiting for service to reach stable state (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!"
echo Service is stable.

REM ── Verify deployment ─────────────────────────────────────────────────────────
echo.
echo -- Deployment Summary -----------------------------------------------------
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}" --output table

echo.
echo CloudWatch Log Group : !LOG_GROUP!
echo AWS Region           : !AWS_REGION!
echo ECS Cluster          : !CLUSTER_NAME!
echo ECS Service          : !SERVICE_NAME!
echo Task Definition      : !TASK_DEF_ARN!

if not "!ALB_DNS!"=="" (
    echo.
    echo Load Balancer DNS    : http://!ALB_DNS!
    echo Health Check URL     : http://!ALB_DNS!/api/health
)

echo.
echo ==============================================
echo   Deployment Complete!
echo ==============================================
echo.
echo Troubleshooting tips:
echo   - View logs  : aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo   - List tasks : aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!

endlocal
