@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-push.bat — Build and push acme-portal-static Docker image (Windows)
:: Supports: AWS ECR and Docker Hub
:: Usage: scripts\build-push.bat  (run from repository root)
:: =============================================================================

set "PROJECT_NAME=acme-portal-static"
set "DOCKERFILE_PATH=Dockerfile"
set "BUILD_CONTEXT=."

echo ==============================================
echo   acme-portal-static -- Docker Build ^& Push
echo ==============================================
echo.

:: ── Registry selection ────────────────────────────────────────────────────────
echo Select container registry:
echo   1) AWS ECR
echo   2) Docker Hub
echo.
set /p REGISTRY_CHOICE="Enter choice [1 or 2]: "

:: ── Image tag ─────────────────────────────────────────────────────────────────
set /p RAW_TAG="Enter image tag (press Enter for 'latest'): "
if "!RAW_TAG!"=="" set "RAW_TAG=latest"

:: Sanitize tag: lowercase via PowerShell
for /f "delims=" %%i in ('powershell -NoProfile -Command "('!RAW_TAG!' -replace '[^a-z0-9._-]','-').ToLower().Trim('-')"') do set "IMAGE_TAG=%%i"
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
echo Using tag: !IMAGE_TAG!
echo.

:: =============================================================================
:: AWS ECR
:: =============================================================================
if "!REGISTRY_CHOICE!"=="1" (
    set /p AWS_REGION="Enter AWS Region (e.g. us-east-1): "
    set /p AWS_ACCOUNT_ID="Enter AWS Account ID (12-digit): "
    set /p ECR_REPO_INPUT="Enter ECR repository name [acme-portal-static]: "
    if "!ECR_REPO_INPUT!"=="" set "ECR_REPO_INPUT=acme-portal-static"
    set "ECR_REPO=!ECR_REPO_INPUT!"

    set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
    set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

    echo.
    echo Authenticating with AWS ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ECR login failed.
        exit /b 1
    )

    echo Checking / creating ECR repository '!ECR_REPO!'...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo Creating ECR repository...
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
        if !ERRORLEVEL! neq 0 (
            echo ERROR: Failed to create ECR repository.
            exit /b 1
        )
    )
    goto BUILD
)

:: =============================================================================
:: Docker Hub
:: =============================================================================
if "!REGISTRY_CHOICE!"=="2" (
    set /p DOCKER_USERNAME="Enter Docker Hub username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub password/token: "
    set /p DOCKER_NAMESPACE_INPUT="Enter Docker Hub namespace/org [leave blank to use username]: "
    if "!DOCKER_NAMESPACE_INPUT!"=="" set "DOCKER_NAMESPACE_INPUT=!DOCKER_USERNAME!"
    set "DOCKER_NAMESPACE=!DOCKER_NAMESPACE_INPUT!"

    set "FULL_IMAGE_NAME=!DOCKER_NAMESPACE!/acme-portal-static:!IMAGE_TAG!"

    echo.
    echo Authenticating with Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed.
        exit /b 1
    )
    goto BUILD
)

echo ERROR: Invalid choice. Please enter 1 or 2.
exit /b 1

:: =============================================================================
:: Build
:: =============================================================================
:BUILD
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo   Dockerfile : !DOCKERFILE_PATH!
echo   Context    : !BUILD_CONTEXT!
echo.
docker build -f "!DOCKERFILE_PATH!" -t "!FULL_IMAGE_NAME!" "!BUILD_CONTEXT!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Build successful.

:: ── Push ──────────────────────────────────────────────────────────────────────
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
