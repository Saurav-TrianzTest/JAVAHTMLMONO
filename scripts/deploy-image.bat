@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: deploy-image.bat - Deploy acme-portal-static to AWS EKS (Windows)
:: =============================================================================

set "APP_NAME=acme-portal-static"
set "NAMESPACE=acme-portal-static"

echo ==============================================
echo   Deploy to AWS EKS: %APP_NAME%
echo ==============================================

:: Prompt for required inputs
set /p "AWS_REGION=Enter AWS Region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
    echo ERROR: AWS Region is required.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter EKS Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/acme-portal-static:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

:: Optional environment variable overrides
echo.
echo --- Optional Environment Variable Configuration ---
set /p "API_URL_INPUT=Enter API_URL (or press Enter to skip): "
if "!API_URL_INPUT!"=="" set "API_URL_INPUT=http://localhost:8080"

echo.
echo Configuring kubectl for EKS cluster: !CLUSTER_NAME! in !AWS_REGION!...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl.
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to EKS cluster.
    exit /b 1
)

:: Determine kubernetes directory relative to this script
set "SCRIPT_DIR=%~dp0"
set "K8S_DIR=%SCRIPT_DIR%..\kubernetes"

:: Update Kubernetes manifests with actual values using PowerShell
echo.
echo Updating Kubernetes manifests with deployment values...

powershell -NoProfile -Command "(Get-Content '%K8S_DIR%\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '%K8S_DIR%\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update IMAGE_URI in deployment.yaml.
    exit /b 1
)

powershell -NoProfile -Command "(Get-Content '%K8S_DIR%\deployment.yaml') -replace '{{API_URL}}', '!API_URL_INPUT!' | Set-Content '%K8S_DIR%\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update API_URL in deployment.yaml.
    exit /b 1
)

:: Apply manifests in order
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "%K8S_DIR%\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.
    exit /b 1
)

echo   [2/4] Applying deployment...
kubectl apply -f "%K8S_DIR%\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.
    exit /b 1
)

echo   [3/4] Applying service...
kubectl apply -f "%K8S_DIR%\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.
    exit /b 1
)

echo   [4/4] Applying ingress...
kubectl apply -f "%K8S_DIR%\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.
    exit /b 1
)

:: Wait for rollout
echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/%APP_NAME% -n %NAMESPACE% --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed.
    echo Rollback command: kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%
    exit /b 1
)

:: Verify resources
echo.
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n %NAMESPACE%

echo.
echo ==============================================
echo   Deployment complete!
echo   Health endpoint: /api/health on port 8080
echo ==============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%

endlocal
exit /b 0
