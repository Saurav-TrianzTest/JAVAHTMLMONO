@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat — Deploy acme-portal-static to GCP GKE (Windows)
REM Usage : scripts\deploy-image.bat  (run from repository root)
REM =============================================================================

set "APP_NAME=acme-portal-static"
set "NAMESPACE=acme-portal-static"

echo ==============================================
echo   Deploy to GCP GKE — %APP_NAME%
echo ==============================================

REM ── Prompt for GCP / GKE details ─────────────────────────────────────────────
set /p "GCP_PROJECT=Enter GCP Project ID: "
if "!GCP_PROJECT!"=="" (
    echo ERROR: GCP Project ID is required.
    exit /b 1
)

set /p "GCP_ZONE=Enter GCP Zone (e.g. us-central1-a) [us-central1-a]: "
if "!GCP_ZONE!"=="" set "GCP_ZONE=us-central1-a"

set /p "CLUSTER_NAME=Enter GKE Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: GKE Cluster Name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI: "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

REM ── Optional environment variable overrides ───────────────────────────────────
echo.
echo --- Optional Environment Variable Overrides ---
echo (Press Enter to keep placeholder values in manifests)
set /p "API_URL_VAL=Enter API_URL value (or press Enter to skip): "

REM ── Configure kubectl ─────────────────────────────────────────────────────────
echo.
echo Configuring kubectl for cluster: !CLUSTER_NAME!...
gcloud container clusters get-credentials !CLUSTER_NAME! --zone !GCP_ZONE! --project !GCP_PROJECT!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl.
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to cluster.
    exit /b 1
)

REM ── Copy manifests to temp directory ─────────────────────────────────────────
set "TEMP_DIR=%TEMP%\k8s-deploy-%APP_NAME%"
if exist "!TEMP_DIR!" rmdir /s /q "!TEMP_DIR!"
xcopy /s /e /i /q kubernetes "!TEMP_DIR!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to copy manifests.
    exit /b 1
)

REM ── Update manifests with actual values ──────────────────────────────────────
echo.
echo Updating Kubernetes manifests...

REM Use PowerShell for sed-like replacement on Windows
powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update IMAGE_URI in deployment.yaml.
    exit /b 1
)

if not "!API_URL_VAL!"=="" (
    powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '\{\{API_URL\}\}', '!API_URL_VAL!' | Set-Content '!TEMP_DIR!\deployment.yaml'"
) else (
    powershell -Command "(Get-Content '!TEMP_DIR!\deployment.yaml') -replace '\{\{API_URL\}\}', '' | Set-Content '!TEMP_DIR!\deployment.yaml'"
)

REM ── Apply Kubernetes manifests ────────────────────────────────────────────────
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "!TEMP_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.
    exit /b 1
)

echo   [2/4] Applying deployment...
kubectl apply -f "!TEMP_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.
    exit /b 1
)

echo   [3/4] Applying service...
kubectl apply -f "!TEMP_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.
    exit /b 1
)

echo   [4/4] Applying ingress...
kubectl apply -f "!TEMP_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.
    exit /b 1
)

REM ── Wait for rollout ──────────────────────────────────────────────────────────
echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/%APP_NAME% -n %NAMESPACE% --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed.
    echo Rollback command: kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%
    exit /b 1
)

REM ── Verify resources ──────────────────────────────────────────────────────────
echo.
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n %NAMESPACE%

echo.
echo ==============================================
echo   Deployment complete!
echo   Application : %APP_NAME%
echo   Namespace   : %NAMESPACE%
echo   Check ingress IP with:
echo   kubectl get ingress -n %NAMESPACE%
echo ==============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%

REM ── Cleanup temp files ────────────────────────────────────────────────────────
if exist "!TEMP_DIR!" rmdir /s /q "!TEMP_DIR!"

endlocal
exit /b 0
