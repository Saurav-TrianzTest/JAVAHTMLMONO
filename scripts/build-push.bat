@echo off
setlocal enabledelayedexpansion

REM =============================================================
REM build-push.bat – Build and push the acme-portal-static Docker
REM image to Azure ACR or Docker Hub.
REM
REM Usage: scripts\build-push.bat
REM Run from the repository root directory.
REM =============================================================

set "PROJECT_NAME=acme-portal-static"

echo ==============================================
echo   acme-portal-static - Docker Build ^& Push
echo ==============================================
echo.

REM ── Sanitize image name (lowercase, replace non-alphanumeric with hyphen) ──
set "IMAGE_NAME=acme-portal-static"

REM ── Prompt for image tag ─────────────────────────────────────
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" (
    set "IMAGE_TAG=latest"
) else (
    set "IMAGE_TAG=!IMAGE_TAG_INPUT!"
)
echo Image tag: !IMAGE_TAG!
echo.

REM ── Registry selection ───────────────────────────────────────
echo Select container registry:
echo   1. Azure Container Registry (ACR)
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :acr_login
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_login
echo ERROR: Invalid registry choice '!REGISTRY_CHOICE!'. Please enter 1 or 2.
exit /b 1

REM ── Azure ACR ──────────────────────────────────────────────
:acr_login
echo.
echo --- Azure Container Registry ---
set /p "ACR_NAME=Enter ACR name (e.g. myregistry): "
if "!ACR_NAME!"=="" (
    echo ERROR: ACR name cannot be empty.
    exit /b 1
)

REM Build full image name for ACR
set "FULL_IMAGE_NAME=!ACR_NAME!.azurecr.io/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Logging in to ACR: !ACR_NAME! ...
az acr login --name !ACR_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ACR login failed.
    exit /b 1
)
goto :build_image

REM ── Docker Hub ─────────────────────────────────────────────
:dockerhub_login
echo.
echo --- Docker Hub ---
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub username cannot be empty.
    exit /b 1
)
set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
if "!DOCKER_PASSWORD!"=="" (
    echo ERROR: Docker Hub password cannot be empty.
    exit /b 1
)

set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Logging in to Docker Hub ...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
goto :build_image

REM ── Build Docker image ───────────────────────────────────────
:build_image
echo.
echo Full image name: !FULL_IMAGE_NAME!
echo.
echo Building Docker image ...
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Docker build succeeded.
echo.

REM ── Push Docker image ────────────────────────────────────────
echo Pushing image to registry ...
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
exit /b 0
