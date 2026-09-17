@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat — Deploy acme-portal-static to AWS EKS (Windows)
REM Usage: scripts\deploy-image.bat  (run from repository root)
REM =============================================================================

set "APP_NAME=acme-portal-static"
set "NAMESPACE=acme-portal-static"

echo ==============================================
echo   Deploy: !APP_NAME! ^-^> AWS EKS
echo ==============================================

REM ── Prompt for AWS / EKS details ─────────────────────────────────────────
set /p "AWS_REGION=Enter AWS region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "CLUSTER_NAME=Enter EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS cluster name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI: "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

REM ── Configure kubectl ─────────────────────────────────────────────────────
echo.
echo Configuring kubectl for cluster: !CLUSTER_NAME! ...
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

REM ── Patch manifests ───────────────────────────────────────────────────────
echo.
echo Updating Kubernetes manifests with image URI...
powershell -NoProfile -Command ^
  "(Get-Content kubernetes\deployment.yaml) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content kubernetes\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment manifest.
    exit /b 1
)

REM ── Apply manifests ───────────────────────────────────────────────────────
echo.
echo Applying Kubernetes manifests...
kubectl apply -f kubernetes\namespace.yaml
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply namespace. & exit /b 1 )

kubectl apply -f kubernetes\deployment.yaml
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply deployment. & exit /b 1 )

kubectl apply -f kubernetes\service.yaml
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply service. & exit /b 1 )

kubectl apply -f kubernetes\ingress.yaml
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply ingress. & exit /b 1 )

REM ── Wait for rollout ──────────────────────────────────────────────────────
echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed.
    echo Rollback command: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

REM ── Verify ────────────────────────────────────────────────────────────────
echo.
echo Deployment resources:
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo ==============================================
echo   Deployment complete!
echo   Check ingress for the application URL.
echo   Health endpoint: /api/health
echo ==============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

endlocal
