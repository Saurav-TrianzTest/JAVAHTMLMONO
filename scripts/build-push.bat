@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM build-push.bat — Build and push the acme-portal-static Docker image
REM Supports: AWS ECR and Docker Hub
REM Usage   : scripts\build-push.bat  (run from repository root)
REM =============================================================================

set "PROJECT_NAME=acme-portal-static"
set "IMAGE_NAME=acme-portal-static"

echo ==============================================
echo   Build ^& Push: !IMAGE_NAME!
echo ==============================================

REM ── Prompt for image tag ──────────────────────────────────────────────────
set /p "INPUT_TAG=Enter image tag [latest]: "
if "!INPUT_TAG!"=="" set "INPUT_TAG=latest"

REM Lowercase via PowerShell
for /f "delims=" %%i in ('powershell -NoProfile -Command "\"!INPUT_TAG!\".ToLower() -replace '[^a-z0-9._-]','-' -replace '^-+','' -replace '-+$',''"') do set "IMAGE_TAG=%%i"
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
echo Using tag: !IMAGE_TAG!

REM ── Registry selection ────────────────────────────────────────────────────
echo.
echo Select container registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :ecr
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub
echo ERROR: Invalid registry choice. Choose 1 or 2.
exit /b 1

REM ── AWS ECR ───────────────────────────────────────────────────────────────
:ecr
set /p "AWS_REGION=Enter AWS region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "AWS_ACCOUNT_ID=Enter AWS account ID: "
if "!AWS_ACCOUNT_ID!"=="" (
    echo ERROR: AWS account ID is required.
    exit /b 1
)

set "ECR_REPO=!IMAGE_NAME!"
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo.
echo Logging in to AWS ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ECR login failed.
    exit /b 1
)

echo Ensuring ECR repository exists...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECR repository.
        exit /b 1
    )
)
goto :build

REM ── Docker Hub ────────────────────────────────────────────────────────────
:dockerhub
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub username is required.
    exit /b 1
)

set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
if "!DOCKER_PASSWORD!"=="" (
    echo ERROR: Docker Hub password/token is required.
    exit /b 1
)

set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
goto :build

REM ── Build ─────────────────────────────────────────────────────────────────
:build
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Build successful.

REM ── Push ──────────────────────────────────────────────────────────────────
echo.
echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Image pushed successfully!
echo   !FULL_IMAGE_NAME!
echo ==============================================

endlocal
