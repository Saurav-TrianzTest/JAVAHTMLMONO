#!/bin/sh
# =============================================================================
# docker-entrypoint.sh
# ECS Fargate / Kubernetes container entry-point script.
#
# Containerization fixes applied by this script:
#   cz-html-1002 – Platform-Specific Path Separators in HTML
#   cz-html-1008 – Localhost Resource References in HTML (CDN_BASE_URL substitution)
#   cz-html-1007 – Hardcoded Port Numbers in HTML Script/Link Tags
# -----------------------------------------------------------------------------
# HTML files that were authored on Windows may contain backslash path separators
# (e.g. href="assets\css\dashboard.css").  Linux containers require forward
# slashes.  This script normalises every backslash inside href="…" and src="…"
# attribute values in all HTML files before the web server starts serving
# requests, guaranteeing cross-platform compatibility in ECS Fargate and
# Kubernetes pods.
#
# cz-html-1007 fix: The ${TELEMETRY_BASE_URL} placeholder inserted in
# pages/dashboard.html (replacing the hardcoded http://localhost:5000 port
# reference) is substituted at container startup using the TELEMETRY_BASE_URL
# environment variable.  This variable must be injected into the ECS Fargate
# task definition via AWS Secrets Manager (secretsmanager ARN mapped to the
# TELEMETRY_BASE_URL environment variable) so that no port number is baked
# into the container image and the same image can be promoted across all
# environments.
# =============================================================================

set -e

HTML_ROOT="${HTML_ROOT:-/app}"

echo "[entrypoint] Normalising Windows backslash path separators in HTML files under ${HTML_ROOT} ..."

# Use find + sed to replace backslashes inside href and src attribute values.
# The sed expression targets the pattern:  (href|src)="…\…"
# and replaces every backslash between the quotes with a forward slash.
# POSIX sed does not support non-greedy quantifiers, so we use a two-pass
# approach: first replace backslashes inside href="…", then inside src="…".
find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r file; do
    # Replace backslashes in href="..." values
    sed -i 's|href="\([^"]*\)\\|href="\1/|g' "${file}"
    # Repeat until no backslashes remain in href values (handles multiple backslashes)
    while grep -q 'href="[^"]*\\' "${file}" 2>/dev/null; do
        sed -i 's|href="\([^"]*\)\\|href="\1/|g' "${file}"
    done

    # Replace backslashes in src="..." values
    sed -i 's|src="\([^"]*\)\\|src="\1/|g' "${file}"
    # Repeat until no backslashes remain in src values
    while grep -q 'src="[^"]*\\' "${file}" 2>/dev/null; do
        sed -i 's|src="\([^"]*\)\\|src="\1/|g' "${file}"
    done

    echo "[entrypoint]   Processed: ${file}"
done

echo "[entrypoint] Path normalisation complete."

# =============================================================================
# CONTAINERIZATION FIX (cz-html-1008): Substitute ${CDN_BASE_URL} placeholder
# in HTML files with the runtime value from AWS Secrets Manager.
# The telemetry asset (previously referenced as http://localhost:5000/js/telemetry.js)
# is now uploaded to Amazon S3 and served via a CloudFront distribution.
# CDN_BASE_URL is injected by ECS Fargate from AWS Secrets Manager so no localhost
# reference is ever baked into the container image, enabling proper container
# networking and service discovery in multi-container / Kubernetes deployments.
# =============================================================================
echo "[entrypoint] Substituting CDN_BASE_URL placeholder in HTML files (cz-html-1008) ..."

CDN_BASE_URL="${CDN_BASE_URL:-}"

if [ -n "${CDN_BASE_URL}" ]; then
    find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r file; do
        sed -i "s|\${CDN_BASE_URL}|${CDN_BASE_URL}|g" "${file}"
        echo "[entrypoint]   Substituted CDN_BASE_URL in: ${file}"
    done
    echo "[entrypoint] CDN_BASE_URL substitution complete."
else
    echo "[entrypoint] WARNING: CDN_BASE_URL is not set. Placeholder will remain in HTML." >&2
fi

# =============================================================================
# CONTAINERIZATION FIX (cz-html-1007): Substitute ${TELEMETRY_BASE_URL}
# placeholder in HTML files with the runtime value from AWS Secrets Manager.
# The TELEMETRY_BASE_URL env var is injected by ECS Fargate from Secrets Manager
# so no hardcoded port number (e.g. :5000) is ever baked into the container image.
# =============================================================================
echo "[entrypoint] Substituting TELEMETRY_BASE_URL placeholder in HTML files ..."

TELEMETRY_BASE_URL="${TELEMETRY_BASE_URL:-}"

if [ -n "${TELEMETRY_BASE_URL}" ]; then
    find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r file; do
        sed -i "s|\${TELEMETRY_BASE_URL}|${TELEMETRY_BASE_URL}|g" "${file}"
        echo "[entrypoint]   Substituted TELEMETRY_BASE_URL in: ${file}"
    done
    echo "[entrypoint] TELEMETRY_BASE_URL substitution complete."
else
    echo "[entrypoint] WARNING: TELEMETRY_BASE_URL is not set. Placeholder will remain in HTML." >&2
fi

# =============================================================================
# CONTAINERIZATION FIX (cz-html-1011): Substitute window.__ENV__ placeholder
# values in HTML files with runtime values from AWS SSM Parameter Store /
# Secrets Manager.  The window.__ENV__ script block in pages/dashboard.html
# (and any other HTML pages) acts as the designated runtime config injection
# point required for ECS Fargate / Kubernetes container deployments.
#
# Variables injected here are sourced from the ECS task definition
# environment / secrets blocks (AWS SSM Parameter Store or Secrets Manager ARNs
# mapped to the corresponding environment variable names).
# =============================================================================
echo "[entrypoint] Substituting window.__ENV__ runtime config placeholders (cz-html-1011) ..."

STATIC_ASSETS_BASE_URL="${STATIC_ASSETS_BASE_URL:-}"
API_BASE_URL="${API_BASE_URL:-}"

if [ -n "${STATIC_ASSETS_BASE_URL}" ]; then
    find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r file; do
        sed -i "s|\${STATIC_ASSETS_BASE_URL}|${STATIC_ASSETS_BASE_URL}|g" "${file}"
        echo "[entrypoint]   Substituted STATIC_ASSETS_BASE_URL in: ${file}"
    done
    echo "[entrypoint] STATIC_ASSETS_BASE_URL substitution complete."
else
    echo "[entrypoint] WARNING: STATIC_ASSETS_BASE_URL is not set. Placeholder will remain in HTML." >&2
fi

if [ -n "${API_BASE_URL}" ]; then
    find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r file; do
        sed -i "s|\${API_BASE_URL}|${API_BASE_URL}|g" "${file}"
        echo "[entrypoint]   Substituted API_BASE_URL in: ${file}"
    done
    echo "[entrypoint] API_BASE_URL substitution complete."
else
    echo "[entrypoint] WARNING: API_BASE_URL is not set. Placeholder will remain in HTML." >&2
fi

echo "[entrypoint] window.__ENV__ runtime config injection complete (cz-html-1011)."

# Hand off to the main application process (passed as CMD arguments).
exec "$@"
