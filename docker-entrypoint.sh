#!/bin/sh
# =============================================================================
# docker-entrypoint.sh
# ECS Fargate Container Entry Point – Path Normalization & Env Injection Script
#
# Rules addressed:
#   cz-html-1002 – Platform-Specific Path Separators in HTML
#   cz-html-1003 – Hardcoded API Endpoints in HTML Forms
#   cz-html-1007 – Hardcoded Port Numbers in HTML Script/Link Tags
#   cz-html-1008 – Localhost Resource References in HTML
#   cz-html-1011 – Missing Runtime Config Injection Point in HTML
#
# Purpose:
#   1. Normalize Windows-style backslash path separators in all HTML files to
#      Linux-compatible forward slashes before the web server begins serving
#      requests. This ensures cross-platform compatibility in Linux containers
#      running on ECS Fargate / Kubernetes pods.
#   2. Inject ECS / Kubernetes environment variables (sourced from AWS Secrets
#      Manager) into window.__ENV__ inside HTML files so that form action URLs
#      and other API endpoints are resolved at container startup rather than
#      being hardcoded in the image.
#   3. Replace __APP_BASE_URL__ placeholder tokens in HTML files with the
#      runtime value of APP_BASE_URL (injected from AWS Secrets Manager via
#      ECS Fargate task definition), eliminating hardcoded port numbers from
#      script/link src attributes.
#   4. Replace __CDN_BASE_URL__ placeholder tokens in HTML files with the
#      runtime value of CDN_BASE_URL (injected from AWS SSM Parameter Store via
#      ECS Fargate task definition), eliminating localhost static-asset references
#      and routing all static asset requests through the CloudFront CDN.
#   5. cz-html-1011: Writes a /config/config.json file to the shared volume so
#      that the window.__ENV__ bootstrap script in HTML pages can fetch runtime
#      configuration at page load.  In ECS Fargate deployments the SSM Agent
#      sidecar container writes this file; this step provides a fallback that
#      assembles config.json from environment variables when the sidecar is not
#      present (e.g. local Docker Compose or CI environments).
#
# Environment variables consumed:
#   HTML_ROOT         – directory to scan for HTML files (default: /app)
#   CONTACT_API_URL   – API endpoint for the contact form
#                       (e.g. https://api.acme-corp.com/v2/contact/submit)
#                       Injected by ECS task definition / Kubernetes ConfigMap
#                       from AWS Secrets Manager.
#   APP_BASE_URL      – canonical application base URL without a port number
#                       (e.g. https://app.acme-corp.com)
#                       Injected by ECS task definition from AWS Secrets Manager
#                       (secret name: acme-portal/app-base-url).
#                       Replaces __APP_BASE_URL__ placeholders in HTML files.
#   CDN_BASE_URL      – CloudFront CDN base URL for static assets
#                       (e.g. https://d1234abcd.cloudfront.net)
#                       Injected by ECS task definition from AWS SSM Parameter Store
#                       (parameter name: /acme-portal/cdn-base-url).
#                       Replaces __CDN_BASE_URL__ placeholders in HTML files.
#   API_BASE_URL      – Base URL for backend API calls exposed via window.__ENV__
#                       (e.g. https://api.acme-corp.com)
#                       Injected by ECS task definition from AWS SSM Parameter Store
#                       (parameter name: /acme-portal/api-base-url).
#   ENV_NAME          – Logical environment name (e.g. production, staging)
#                       Injected by ECS task definition from AWS SSM Parameter Store.
#
# Usage (Dockerfile):
#   COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
#   RUN chmod +x /usr/local/bin/docker-entrypoint.sh
#   ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# =============================================================================

set -e

HTML_ROOT="${HTML_ROOT:-/app}"

# ---------------------------------------------------------------------------
# Step 1 – cz-html-1002: Normalize backslash path separators in HTML files
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting path normalization for HTML files under: ${HTML_ROOT}"

find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r html_file; do
    if grep -qP '(href|src)="[^"]*\\[^"]*"' "${html_file}" 2>/dev/null || \
       grep -q 'href="[^"]*\\[^"]*"\|src="[^"]*\\[^"]*"' "${html_file}" 2>/dev/null; then
        echo "[entrypoint] Normalizing backslash paths in: ${html_file}"
        sed -i 's|\(href="[^"]*\)\\\([^"]*"\)|\1/\2|g;
                s|\(src="[^"]*\)\\\([^"]*"\)|\1/\2|g' "${html_file}"
        for i in 1 2 3; do
            sed -i 's|\(href="[^"]*\)\\\([^"]*"\)|\1/\2|g;
                    s|\(src="[^"]*\)\\\([^"]*"\)|\1/\2|g' "${html_file}"
        done
        echo "[entrypoint] Done normalizing: ${html_file}"
    fi
done

echo "[entrypoint] Path normalization complete."

# ---------------------------------------------------------------------------
# Step 2 – cz-html-1003: Inject API endpoint environment variables into
#           window.__ENV__ inside HTML files.
#
# The placeholder token  __CONTACT_API_URL__  is replaced with the runtime
# value of the CONTACT_API_URL environment variable (injected by ECS Fargate
# task definition from AWS Secrets Manager).  This keeps every environment-
# specific URL out of the container image while still making the value
# available to client-side JavaScript via window.__ENV__.
# ---------------------------------------------------------------------------
echo "[entrypoint] Injecting API endpoint environment variables into HTML files."

CONTACT_API_URL="${CONTACT_API_URL:-}"

if [ -z "${CONTACT_API_URL}" ]; then
    echo "[entrypoint] WARNING: CONTACT_API_URL is not set. Contact form submissions will be disabled."
fi

find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r html_file; do
    # Inject CONTACT_API_URL into window.__ENV__ bootstrap block
    if grep -q 'window\.__ENV__' "${html_file}" 2>/dev/null; then
        echo "[entrypoint] Injecting CONTACT_API_URL into: ${html_file}"
        # Replace the bare window.__ENV__ initializer with one that carries
        # the runtime value so the inline JS in contact.html can read it.
        sed -i "s|window\.__ENV__ = window\.__ENV__ || {};|window.__ENV__ = window.__ENV__ || {}; window.__ENV__.CONTACT_API_URL = '${CONTACT_API_URL}';|g" "${html_file}"
        echo "[entrypoint] Done injecting into: ${html_file}"
    fi
done

echo "[entrypoint] Environment variable injection complete."

# ---------------------------------------------------------------------------
# Step 3 – cz-html-1007: Replace __APP_BASE_URL__ placeholder tokens in HTML
#           files with the runtime value of APP_BASE_URL (injected from AWS
#           Secrets Manager via ECS Fargate task definition).
#
# This eliminates hardcoded port numbers (e.g. :5000, :8080, :3000) from
# script src and link href attributes.  The placeholder __APP_BASE_URL__ is
# written into the HTML at build time; the actual base URL (using standard
# ports 80/443 enforced by the Kubernetes/ECS service layer) is substituted
# here at container startup so no port-specific URL is ever baked into the
# container image.
# ---------------------------------------------------------------------------
echo "[entrypoint] Substituting __APP_BASE_URL__ placeholders in HTML files."

APP_BASE_URL="${APP_BASE_URL:-}"

if [ -z "${APP_BASE_URL}" ]; then
    echo "[entrypoint] WARNING: APP_BASE_URL is not set. Script/link src placeholders will remain unresolved."
fi

find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r html_file; do
    if grep -q '__APP_BASE_URL__' "${html_file}" 2>/dev/null; then
        echo "[entrypoint] Substituting APP_BASE_URL in: ${html_file}"
        sed -i "s|__APP_BASE_URL__|${APP_BASE_URL}|g" "${html_file}"
        echo "[entrypoint] Done substituting in: ${html_file}"
    fi
done

echo "[entrypoint] APP_BASE_URL substitution complete."

# ---------------------------------------------------------------------------
# Step 4 – cz-html-1008: Replace __CDN_BASE_URL__ placeholder tokens in HTML
#           files with the runtime value of CDN_BASE_URL (injected from AWS
#           SSM Parameter Store via ECS Fargate task definition).
#
# This eliminates localhost static-asset references (e.g. http://localhost:5000/
# js/telemetry.js) from HTML files.  Static assets are uploaded to Amazon S3
# and served through a CloudFront distribution.  The placeholder __CDN_BASE_URL__
# is written into the HTML at build time; the actual CloudFront CDN base URL is
# substituted here at container startup so no localhost URL is ever baked into
# the container image, enabling proper container networking and service discovery
# in multi-container / Kubernetes pod deployments.
# ---------------------------------------------------------------------------
echo "[entrypoint] Substituting __CDN_BASE_URL__ placeholders in HTML files."

CDN_BASE_URL="${CDN_BASE_URL:-}"

if [ -z "${CDN_BASE_URL}" ]; then
    echo "[entrypoint] WARNING: CDN_BASE_URL is not set. Localhost static-asset placeholders will remain unresolved."
fi

find "${HTML_ROOT}" -type f -name "*.html" | while IFS= read -r html_file; do
    if grep -q '__CDN_BASE_URL__' "${html_file}" 2>/dev/null; then
        echo "[entrypoint] Substituting CDN_BASE_URL in: ${html_file}"
        sed -i "s|__CDN_BASE_URL__|${CDN_BASE_URL}|g" "${html_file}"
        echo "[entrypoint] Done substituting in: ${html_file}"
    fi
done

echo "[entrypoint] CDN_BASE_URL substitution complete."

# ---------------------------------------------------------------------------
# Step 5 – cz-html-1011: Write /config/config.json for window.__ENV__ bootstrap.
#
# In a production ECS Fargate deployment the SSM Agent sidecar container reads
# parameters from AWS SSM Parameter Store and writes config.json to the shared
# volume BEFORE this container starts (enforced by ECS container dependency
# ordering: START condition on the sidecar).  This step acts as a safety-net
# fallback: if config.json does not yet exist (e.g. local Docker Compose, CI,
# or the sidecar has not written the file yet) it assembles the file from the
# environment variables that are already available in this container so that
# the window.__ENV__ fetch in dashboard.html always resolves successfully.
#
# The generated file is served by the Java HttpServer at GET /config/config.json
# (registered in Application.java alongside /api/health).
#
# SSM Parameter Store mappings (written by the sidecar in production):
#   /acme-portal/api-base-url      → API_BASE_URL
#   /acme-portal/cdn-base-url      → CDN_BASE_URL
#   /acme-portal/admin-console-url → ADMIN_CONSOLE_URL
#   /acme-portal/env-name          → ENV_NAME
# ---------------------------------------------------------------------------
echo "[entrypoint] Ensuring /config/config.json exists for window.__ENV__ bootstrap."

CONFIG_DIR="${HTML_ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Only write the fallback file if the sidecar has not already written it.
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "[entrypoint] config.json not found – writing fallback from environment variables."
    mkdir -p "${CONFIG_DIR}"

    API_BASE_URL="${API_BASE_URL:-}"
    CDN_BASE_URL="${CDN_BASE_URL:-}"
    ADMIN_CONSOLE_URL="${ADMIN_CONSOLE_URL:-}"
    ENV_NAME="${ENV_NAME:-}"
    CONTACT_API_URL="${CONTACT_API_URL:-}"

    cat > "${CONFIG_FILE}" <<EOF
{
  "API_BASE_URL": "${API_BASE_URL}",
  "CDN_BASE_URL": "${CDN_BASE_URL}",
  "ADMIN_CONSOLE_URL": "${ADMIN_CONSOLE_URL}",
  "CONTACT_API_URL": "${CONTACT_API_URL}",
  "ENV_NAME": "${ENV_NAME}"
}
EOF
    echo "[entrypoint] Fallback config.json written to: ${CONFIG_FILE}"
else
    echo "[entrypoint] config.json already present (written by SSM sidecar). Skipping fallback write."
fi

echo "[entrypoint] Runtime config injection point setup complete."

# Hand off to the main application process
exec "$@"
