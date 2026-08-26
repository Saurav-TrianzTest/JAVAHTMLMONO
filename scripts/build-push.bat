@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-push.bat - Build and push Docker image for acme-portal-static
:: Target: AWS ECR or Docker Hub
:: =============================================================================

set "PROJECT_NAME=acme-portal-static"

echo ==============================================
echo   Build ^& Push: %PROJECT_NAME%
echo ==============================================

:: Sanitize image name using PowerShell
for /f "delims=" %%i in ('powershell -NoProfile -Command "$n = '%PROJECT_NAME%'.ToLower() -replace '[^a-z0-9]+','-'; $n.Trim('-')"') do set "IMAGE_NAME=%%i"

:: Prompt for image tag
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" (
    set "IMAGE_TAG=latest"
) else (
    for /f "delims=" %%i in ('powershell -NoProfile -Command "$t = '!IMAGE_TAG_INPUT!'.ToLower() -replace '[^a-z0-9._-]+','-'; $t.Trim('-')"') do set "IMAGE_TAG=%%i"
    if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
)

echo.
echo Select container registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1 or 2]: "

if "!REGISTRY_CHOICE!"=="1" goto :ecr
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub
echo Invalid choice. Exiting.
exit /b 1

:ecr
set /p "AWS_REGION=Enter AWS Region (e.g. us-east-1): "
set /p "AWS_ACCOUNT_ID=Enter AWS Account ID: "

set "ECR_REPO=!IMAGE_NAME!"
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo.
echo Logging in to AWS ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ECR login failed.
    exit /b 1
)

echo Ensuring ECR repository exists...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo Failed to create ECR repository.
        exit /b 1
    )
)
goto :build

:dockerhub
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
set /p "DOCKER_REPO=Enter Docker Hub repository (e.g. myorg/!IMAGE_NAME!): "

set "FULL_IMAGE_NAME=!DOCKER_REPO!:!IMAGE_TAG!"

echo.
echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo Docker Hub login failed.
    exit /b 1
)
goto :build

:build
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo Docker build failed.
    exit /b 1
)

echo.
echo Pushing Docker image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Successfully pushed: !FULL_IMAGE_NAME!
echo ==============================================

endlocal
exit /b 0
