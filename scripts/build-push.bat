@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM build-push.bat — Build and push Docker image for acme-portal-static
REM Target: GCP GKE
REM Usage : scripts\build-push.bat  (run from repository root)
REM =============================================================================

set "PROJECT_NAME=acme-portal-static"

echo ==============================================
echo   Build ^& Push — %PROJECT_NAME%
echo ==============================================

REM ── Sanitize image name (lowercase, hyphens only) ────────────────────────────
set "IMAGE_NAME=acme-portal-static"

REM ── Prompt for image tag ──────────────────────────────────────────────────────
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" (
    set "IMAGE_TAG=latest"
) else (
    set "IMAGE_TAG=!IMAGE_TAG_INPUT!"
)
echo Using image tag: !IMAGE_TAG!

REM ── Registry selection ────────────────────────────────────────────────────────
echo.
echo Select container registry:
echo   1^) Google Artifact Registry
echo   2^) Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :artifact_registry
if "!REGISTRY_CHOICE!"=="2" goto :docker_hub
echo ERROR: Invalid registry choice '!REGISTRY_CHOICE!'.
exit /b 1

REM ── Google Artifact Registry ──────────────────────────────────────────────────
:artifact_registry
echo.
echo --- Google Artifact Registry ---
set /p "GCP_PROJECT=Enter GCP Project ID: "
if "!GCP_PROJECT!"=="" (
    echo ERROR: GCP Project ID is required.
    exit /b 1
)

set /p "GCP_REGION=Enter GCP Region (e.g. us-central1) [us-central1]: "
if "!GCP_REGION!"=="" set "GCP_REGION=us-central1"

set /p "AR_REPO=Enter Artifact Registry repository name [!IMAGE_NAME!]: "
if "!AR_REPO!"=="" set "AR_REPO=!IMAGE_NAME!"

set "FULL_IMAGE_NAME=!GCP_REGION!-docker.pkg.dev/!GCP_PROJECT!/!AR_REPO!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Authenticating with Google Artifact Registry...
gcloud auth configure-docker !GCP_REGION!-docker.pkg.dev --quiet
if !ERRORLEVEL! neq 0 (
    echo ERROR: Artifact Registry authentication failed.
    exit /b 1
)
goto :build_image

REM ── Docker Hub ────────────────────────────────────────────────────────────────
:docker_hub
echo.
echo --- Docker Hub ---
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
echo Authenticating with Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub authentication failed.
    exit /b 1
)
goto :build_image

REM ── Build Docker image ────────────────────────────────────────────────────────
:build_image
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo Build context: . (repository root)
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Docker build succeeded.

echo.
echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)
echo Docker push succeeded.

echo.
echo ==============================================
echo   Image pushed successfully!
echo   !FULL_IMAGE_NAME!
echo ==============================================

endlocal
exit /b 0
