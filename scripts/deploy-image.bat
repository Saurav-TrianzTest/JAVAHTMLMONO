@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: deploy-image.bat — Deploy acme-portal-static to AWS ECS Fargate (Windows)
:: Usage: scripts\deploy-image.bat  (run from repository root)
:: =============================================================================

set "SERVICE_NAME=acme-portal-static-service"
set "TASK_FAMILY=acme-portal-static-task"
set "LOG_GROUP=/ecs/acme-portal-static"
set "TASK_DEF_FILE=ecs\task-definition.json"
set "SERVICE_DEF_FILE=ecs\service-definition.json"

echo ============================================================
echo   acme-portal-static -- AWS ECS Fargate Deployment
echo ============================================================
echo.

:: ── Gather inputs ─────────────────────────────────────────────────────────────
set /p AWS_REGION="Enter AWS Region (e.g. us-east-1): "
set /p CLUSTER_INPUT="Enter ECS Cluster name [acme-portal-static-cluster]: "
if "!CLUSTER_INPUT!"=="" set "CLUSTER_INPUT=acme-portal-static-cluster"
set "CLUSTER_NAME=!CLUSTER_INPUT!"

set /p IMAGE_URI="Enter ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): "
set /p SUBNET_1="Enter Subnet ID 1 (e.g. subnet-xxxxxxxx): "
set /p SUBNET_2="Enter Subnet ID 2 (e.g. subnet-yyyyyyyy): "
set /p SECURITY_GROUP="Enter Security Group ID (e.g. sg-xxxxxxxx): "

:: ── Derive Account ID ─────────────────────────────────────────────────────────
echo.
echo Retrieving AWS Account ID...
for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text') do set "ACCOUNT_ID=%%i"
echo Account ID: !ACCOUNT_ID!

:: ── Ensure CloudWatch log group exists ────────────────────────────────────────
echo.
echo Ensuring CloudWatch log group '!LOG_GROUP!' exists...
aws logs create-log-group --log-group-name "!LOG_GROUP!" --region "!AWS_REGION!" >nul 2>&1

:: ── Ensure ECS cluster exists ─────────────────────────────────────────────────
echo Checking ECS cluster '!CLUSTER_NAME!'...
for /f "tokens=*" %%i in ('aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" --query "clusters[0].status" --output text 2^>nul') do set "CLUSTER_STATUS=%%i"
if not "!CLUSTER_STATUS!"=="ACTIVE" (
    echo Creating ECS cluster '!CLUSTER_NAME!'...
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster.
        exit /b 1
    )
)

:: ── Load Balancer ─────────────────────────────────────────────────────────────
echo.
set /p NEED_ALB="Do you need an Application Load Balancer for this service? (y/n): "
set "USE_ALB=false"

if /i "!NEED_ALB!"=="y" (
    set /p VPC_ID="Enter VPC ID for the load balancer (e.g. vpc-xxxxxxxx): "
    set /p ALB_NAME_INPUT="Enter a name for the ALB [acme-portal-static-alb]: "
    if "!ALB_NAME_INPUT!"=="" set "ALB_NAME_INPUT=acme-portal-static-alb"
    set "ALB_NAME=!ALB_NAME_INPUT!"
    set /p TG_NAME_INPUT="Enter a name for the Target Group [acme-portal-static-tg]: "
    if "!TG_NAME_INPUT!"=="" set "TG_NAME_INPUT=acme-portal-static-tg"
    set "TG_NAME=!TG_NAME_INPUT!"

    echo.
    echo Creating Application Load Balancer '!ALB_NAME!'...
    for /f "tokens=*" %%i in ('aws elbv2 create-load-balancer --name "!ALB_NAME!" --subnets "!SUBNET_1!" "!SUBNET_2!" --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text') do set "ALB_ARN=%%i"
    echo ALB ARN: !ALB_ARN!

    echo Creating Target Group '!TG_NAME!'...
    for /f "tokens=*" %%i in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 8080 --vpc-id "!VPC_ID!" --target-type ip --health-check-path "/api/health" --health-check-interval-seconds 30 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text') do set "TARGET_GROUP_ARN=%%i"
    echo Target Group ARN: !TARGET_GROUP_ARN!

    echo Creating ALB Listener on port 80...
    aws elbv2 create-listener --load-balancer-arn "!ALB_ARN!" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=!TARGET_GROUP_ARN!" --region "!AWS_REGION!" >nul

    for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns "!ALB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text') do set "ALB_DNS=%%i"

    set "USE_ALB=true"
)

:: ── Prepare working copies of JSON files ─────────────────────────────────────
echo.
echo Preparing deployment files...
copy /Y "!TASK_DEF_FILE!" "%TEMP%\task-definition-deploy.json" >nul
copy /Y "!SERVICE_DEF_FILE!" "%TEMP%\service-definition-deploy.json" >nul

:: Substitute placeholders using PowerShell
powershell -NoProfile -Command ^
  "(Get-Content '%TEMP%\task-definition-deploy.json') -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content '%TEMP%\task-definition-deploy.json'"

powershell -NoProfile -Command ^
  "(Get-Content '%TEMP%\service-definition-deploy.json') -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '{{SUBNET_1}}','!SUBNET_1!' -replace '{{SUBNET_2}}','!SUBNET_2!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content '%TEMP%\service-definition-deploy.json'"

if "!USE_ALB!"=="true" (
    powershell -NoProfile -Command ^
      "(Get-Content '%TEMP%\service-definition-deploy.json') -replace '{{TARGET_GROUP_ARN}}','!TARGET_GROUP_ARN!' | Set-Content '%TEMP%\service-definition-deploy.json'"
)

:: ── Register task definition ──────────────────────────────────────────────────
echo Registering ECS task definition...
for /f "tokens=*" %%i in ('aws ecs register-task-definition --cli-input-json file://%TEMP%\task-definition-deploy.json --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text') do set "TASK_DEF_ARN=%%i"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to register task definition.
    exit /b 1
)
echo Task Definition ARN: !TASK_DEF_ARN!

:: ── Create or update ECS service ──────────────────────────────────────────────
echo.
for /f "tokens=*" %%i in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[?status==''ACTIVE''].serviceName" --output text 2^>nul') do set "EXISTING_SERVICE=%%i"

if "!EXISTING_SERVICE!"=="" (
    echo Creating ECS service '!SERVICE_NAME!'...
    powershell -NoProfile -Command ^
      "$s = Get-Content '%TEMP%\service-definition-deploy.json' | ConvertFrom-Json; $s.taskDefinition = '!TASK_DEF_ARN!'; $s | ConvertTo-Json -Depth 10 | Set-Content '%TEMP%\service-definition-deploy.json'"
    aws ecs create-service --cli-input-json file://%TEMP%\service-definition-deploy.json --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service.
        exit /b 1
    )
) else (
    echo Updating existing ECS service '!SERVICE_NAME!'...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "!SERVICE_NAME!" --task-definition "!TASK_DEF_ARN!" --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service.
        exit /b 1
    )
)

:: ── Wait for stability ────────────────────────────────────────────────────────
echo.
echo Waiting for service to stabilize (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!"

:: ── Verify deployment ─────────────────────────────────────────────────────────
echo.
echo Deployment complete. Service status:
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}" --output table

echo.
echo ============================================================
echo   Deployment Summary
echo ============================================================
echo   Cluster      : !CLUSTER_NAME!
echo   Service      : !SERVICE_NAME!
echo   Task Def ARN : !TASK_DEF_ARN!
echo   CloudWatch   : !LOG_GROUP!
if "!USE_ALB!"=="true" echo   ALB DNS      : http://!ALB_DNS!
echo ============================================================
echo.
echo Troubleshooting tips:
echo   View logs  : aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo   List tasks : aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!

endlocal
