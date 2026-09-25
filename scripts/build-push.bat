@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM build-push.bat – acme-portal-static (JAVAHTMLMONO)
REM Build Docker image and push to AWS ECR or Docker Hub
REM Usage: scripts\build-push.bat
REM Run from repository root directory
REM =============================================================================

set "PROJECT_NAME=acme-portal-static"
set "DOCKERFILE_PATH=Dockerfile"
set "BUILD_CONTEXT=."

echo ==============================================
echo   acme-portal-static - Build ^& Push Script
echo ==============================================
echo.

REM ── Tag sanitisation (via PowerShell) ────────────────────────────────────────
for /f "delims=" %%i in ('powershell -NoProfile -Command "$n = 'acme-portal-static'; $n = $n.ToLower() -replace '[^a-z0-9]+','-'; $n = $n.Trim('-'); Write-Output $n"') do set "IMAGE_NAME=%%i"

echo Project name  : %PROJECT_NAME%
echo Image name    : %IMAGE_NAME%
echo.

REM ── Prompt for image tag ──────────────────────────────────────────────────────
set /p "RAW_TAG=Enter image tag [latest]: "
if "!RAW_TAG!"=="" set "RAW_TAG=latest"

for /f "delims=" %%i in ('powershell -NoProfile -Command "$t = '!RAW_TAG!'; $t = $t.ToLower() -replace '[^a-z0-9._-]+','-'; $t = $t.Trim('-'); if ($t -eq '') { $t = 'latest' }; Write-Output $t"') do set "IMAGE_TAG=%%i"

echo Image tag     : !IMAGE_TAG!
echo.

REM ── Registry selection ────────────────────────────────────────────────────────
echo Select container registry:
echo   1) AWS ECR
echo   2) Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :ecr_setup
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_setup
echo ERROR: Invalid registry choice '!REGISTRY_CHOICE!'. Exiting.
exit /b 1

REM ── AWS ECR ──────────────────────────────────────────────────────────────────
:ecr_setup
echo.
echo -- AWS ECR Configuration --------------------------------------------------
set /p "AWS_REGION=AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "AWS_ACCOUNT_ID=AWS Account ID (leave blank to auto-detect): "
if "!AWS_ACCOUNT_ID!"=="" (
    echo Fetching AWS Account ID from STS...
    for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text 2^>^&1') do set "AWS_ACCOUNT_ID=%%i"
    echo Account ID    : !AWS_ACCOUNT_ID!
)

set /p "ECR_REPO=ECR Repository name [!IMAGE_NAME!]: "
if "!ECR_REPO!"=="" set "ECR_REPO=!IMAGE_NAME!"

set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo.
echo Registry URL  : !REGISTRY_URL!
echo Full image    : !FULL_IMAGE_NAME!
echo.

REM Authenticate to ECR
echo Authenticating to AWS ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ECR authentication failed.
    exit /b 1
)
echo ECR authentication successful.

REM Auto-create ECR repository if it does not exist
echo Checking ECR repository '!ECR_REPO!'...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository '!ECR_REPO!'...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECR repository.
        exit /b 1
    )
)
echo ECR repository ready.
goto :build_image

REM ── Docker Hub ────────────────────────────────────────────────────────────────
:dockerhub_setup
echo.
echo -- Docker Hub Configuration -----------------------------------------------
set /p "DOCKER_USERNAME=Docker Hub username: "
set /p "DOCKER_PASSWORD=Docker Hub password/token: "
set /p "DOCKER_NAMESPACE=Docker Hub namespace/org [!DOCKER_USERNAME!]: "
if "!DOCKER_NAMESPACE!"=="" set "DOCKER_NAMESPACE=!DOCKER_USERNAME!"

set "FULL_IMAGE_NAME=!DOCKER_NAMESPACE!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Full image    : !FULL_IMAGE_NAME!
echo.

REM Authenticate to Docker Hub
echo Authenticating to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub authentication failed.
    exit /b 1
)
echo Docker Hub authentication successful.
goto :build_image

REM ── Build Docker image ────────────────────────────────────────────────────────
:build_image
echo.
echo Building Docker image...
echo   Dockerfile : %DOCKERFILE_PATH%
echo   Context    : %BUILD_CONTEXT%
echo   Tag        : !FULL_IMAGE_NAME!
echo.

docker build -f "%DOCKERFILE_PATH%" -t "!FULL_IMAGE_NAME!" "%BUILD_CONTEXT%"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Docker build successful.

REM ── Push Docker image ─────────────────────────────────────────────────────────
echo.
echo Pushing image to registry...
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Build ^& Push Complete!
echo   Image: !FULL_IMAGE_NAME!
echo ==============================================
echo.
echo Next step: Run scripts\deploy-image.bat to deploy to AWS ECS Fargate.

endlocal
