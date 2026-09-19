@echo off
setlocal enabledelayedexpansion

REM =============================================================
REM deploy-image.bat — Deploy csat to AWS EKS (Windows)
REM Usage: scripts\deploy-image.bat  (from repo root)
REM =============================================================

set "APP_NAME=csat"
set "NAMESPACE=csat"
set "K8S_DIR=kubernetes"

echo =============================================
echo   Deploy %APP_NAME% to AWS EKS
echo =============================================

REM ── Collect deployment inputs ────────────────────────────────
set /p "AWS_REGION=Enter AWS region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
    echo ERROR: AWS region is required.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS cluster name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/csat:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

REM ── Optional environment variable prompts ────────────────────
echo.
echo Optional: Configure application environment variables.
echo (Press Enter to skip any variable)

set /p "API_URL_VAL=Enter value for API_URL (e.g. https://api.example.com): "
if "!API_URL_VAL!"=="" set "API_URL_VAL=http://localhost:8080"

REM ── Update Kubernetes manifests ──────────────────────────────
echo.
echo Updating Kubernetes manifests...

powershell -NoProfile -Command ^
  "(Get-Content '%K8S_DIR%\deployment.yaml') -replace '{{IMAGE_URI}}','!IMAGE_URI!' | Set-Content '%K8S_DIR%\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment.yaml with image URI.
    exit /b 1
)

powershell -NoProfile -Command ^
  "(Get-Content '%K8S_DIR%\deployment.yaml') -replace '{{API_URL}}','!API_URL_VAL!' | Set-Content '%K8S_DIR%\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment.yaml with API_URL.
    exit /b 1
)

echo Manifests updated.

REM ── Configure kubectl for EKS ────────────────────────────────
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
    echo ERROR: Cannot connect to cluster.
    exit /b 1
)

REM ── Apply manifests in order ─────────────────────────────────
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "%K8S_DIR%\namespace.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply namespace. & exit /b 1 )

echo   [2/4] Applying deployment...
kubectl apply -f "%K8S_DIR%\deployment.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply deployment. & exit /b 1 )

echo   [3/4] Applying service...
kubectl apply -f "%K8S_DIR%\service.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply service. & exit /b 1 )

echo   [4/4] Applying ingress...
kubectl apply -f "%K8S_DIR%\ingress.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply ingress. & exit /b 1 )

REM ── Wait for rollout ─────────────────────────────────────────
echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/%APP_NAME% -n %NAMESPACE% --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed.
    echo Rollback command: kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%
    exit /b 1
)

REM ── Verify resources ─────────────────────────────────────────
echo.
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n %NAMESPACE%

echo.
echo =============================================
echo   DEPLOYMENT COMPLETE
echo   Application : %APP_NAME%
echo   Namespace   : %NAMESPACE%
echo   Image       : !IMAGE_URI!
echo =============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/%APP_NAME% -n %NAMESPACE%

endlocal
