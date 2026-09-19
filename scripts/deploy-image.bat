@echo off
setlocal enabledelayedexpansion

REM =============================================================
REM deploy-image.bat – Deploy acme-portal-static to Azure AKS
REM
REM Usage: scripts\deploy-image.bat
REM Run from the repository root directory.
REM Prerequisites: azure-cli, kubectl
REM =============================================================

set "APP_NAME=acme-portal-static"
set "NAMESPACE=acme-portal-static"

echo ==============================================
echo   acme-portal-static - Deploy to Azure AKS
echo ==============================================
echo.

REM ── Prompt for Azure details ─────────────────────────────────
set /p "RESOURCE_GROUP=Enter Azure Resource Group name: "
if "!RESOURCE_GROUP!"=="" (
    echo ERROR: Resource group cannot be empty.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter AKS Cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: AKS cluster name cannot be empty.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g. myregistry.azurecr.io/acme-portal-static:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI cannot be empty.
    exit /b 1
)

REM ── Prompt for optional environment variables ─────────────────
echo.
echo --- Optional Environment Variables ---
echo (Press Enter to skip any variable)
set /p "API_URL_VAL=Enter value for API_URL (e.g. https://api.example.com): "
if "!API_URL_VAL!"=="" set "API_URL_VAL=http://localhost:8080"

REM ── Configure kubectl for AKS ────────────────────────────────
echo.
echo Configuring kubectl for AKS cluster: !CLUSTER_NAME! ...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to get AKS credentials.
    exit /b 1
)

REM ── Verify cluster connectivity ──────────────────────────────
echo.
echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to Kubernetes cluster.
    exit /b 1
)

REM ── Create temp directory for manifests ──────────────────────
set "DEPLOY_DIR=%TEMP%\acme-portal-deploy-%RANDOM%"
mkdir "!DEPLOY_DIR!"

copy kubernetes\namespace.yaml  "!DEPLOY_DIR!\namespace.yaml"  >nul
copy kubernetes\deployment.yaml "!DEPLOY_DIR!\deployment.yaml" >nul
copy kubernetes\service.yaml    "!DEPLOY_DIR!\service.yaml"    >nul
copy kubernetes\ingress.yaml    "!DEPLOY_DIR!\ingress.yaml"    >nul

REM ── Replace placeholders using PowerShell ────────────────────
echo.
echo Preparing Kubernetes manifests ...

powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update IMAGE_URI placeholder.
    exit /b 1
)

powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{API_URL\}\}', '!API_URL_VAL!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update API_URL placeholder.
    exit /b 1
)

powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{NAMESPACE\}\}', '!NAMESPACE!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update NAMESPACE placeholder.
    exit /b 1
)

REM ── Apply manifests in order ─────────────────────────────────
echo.
echo Applying Kubernetes manifests ...

echo   [1/4] Applying namespace ...
kubectl apply -f "!DEPLOY_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.
    exit /b 1
)

echo   [2/4] Applying deployment ...
kubectl apply -f "!DEPLOY_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.
    exit /b 1
)

echo   [3/4] Applying service ...
kubectl apply -f "!DEPLOY_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.
    exit /b 1
)

echo   [4/4] Applying ingress ...
kubectl apply -f "!DEPLOY_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.
    exit /b 1
)

REM ── Wait for rollout ─────────────────────────────────────────
echo.
echo Waiting for deployment rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo.
    echo ERROR: Deployment rollout failed. Rolling back ...
    kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    echo Rollback initiated. Check pod logs:
    echo   kubectl logs -l app=!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

REM ── Verify resources ─────────────────────────────────────────
echo.
echo Verifying deployed resources ...
kubectl get pods,svc,ingress -n !NAMESPACE!

REM ── Display access URL ───────────────────────────────────────
echo.
echo ==============================================
echo   Deployment complete!
echo   Application URL: http://acme-portal-static.example.com
echo   Health endpoint: http://acme-portal-static.example.com/api/health
echo.
echo   Useful commands:
echo     kubectl get pods -n !NAMESPACE!
echo     kubectl logs -l app=!APP_NAME! -n !NAMESPACE!
echo     kubectl describe deployment !APP_NAME! -n !NAMESPACE!
echo     kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
echo ==============================================

REM ── Cleanup temp dir ─────────────────────────────────────────
rmdir /s /q "!DEPLOY_DIR!" 2>nul

endlocal
exit /b 0
