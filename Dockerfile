# =============================================================================
# Dockerfile – acme-portal-static (JAVAHTMLGIT)
#
# Multi-stage build:
#   Stage 1 (builder): Maven 3.9.4 + Eclipse Temurin 17 JDK – compiles the JAR
#   Stage 2 (runtime): mcr.microsoft.com/openjdk/jdk:17-ubuntu – minimal runtime
#
# Remediations applied:
#   cz-html-1012: Build Artifacts Included in HTML Container
#   cz-html-1010: Development HTML Files in Production Container
#   cz-html-1002: Platform-Specific Path Separators in HTML
#   cz-html-1003: Hardcoded API Endpoints in HTML Forms
#   cz-html-1007: Hardcoded Port Numbers in HTML Script/Link Tags
#   cz-html-1008: Localhost Resource References in HTML
#   cz-html-1011: Missing Runtime Config Injection Point in HTML
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy dependency descriptor first for layer caching
COPY pom.xml .

# Download all dependencies (cached layer – only invalidated when pom.xml changes)
RUN mvn dependency:go-offline -B -q

# Copy source code and build the JAR
COPY src ./src
RUN mvn clean package -DskipTests -B -q

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM mcr.microsoft.com/openjdk/jdk:17-ubuntu

# Non-root user for security best practices
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy compiled JAR from builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar /app/acme-portal-static.jar

# Copy static HTML assets (path normalization applied at startup by entrypoint)
COPY pages      ./pages
COPY app        ./app
COPY assets     ./assets
COPY partials   ./partials
COPY forms      ./forms
COPY index.html ./index.html
# NOTE: build-info.html is intentionally excluded (cz-html-1012)
# NOTE: test.html is intentionally excluded (cz-html-1010)

# cz-html-1011: Create the config directory for the shared volume mount point.
# In ECS Fargate the SSM Agent sidecar writes config.json here before the main
# container starts. docker-entrypoint.sh writes a fallback when sidecar is absent.
RUN mkdir -p /app/config

# Copy and register the ENTRYPOINT script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ── Environment variables ─────────────────────────────────────────────────────
# HTML_ROOT tells the entrypoint where to scan for HTML files
ENV HTML_ROOT=/app

# JVM tuning – container-aware memory settings
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Dfile.encoding=UTF-8 -Duser.timezone=UTC"

# cz-html-1003: CONTACT_API_URL injected at runtime from AWS Secrets Manager
ENV CONTACT_API_URL=""

# cz-html-1007: APP_BASE_URL injected at runtime from AWS Secrets Manager
ENV APP_BASE_URL=""

# cz-html-1008: CDN_BASE_URL injected at runtime from AWS SSM Parameter Store
ENV CDN_BASE_URL=""

# cz-html-1011: Runtime config environment variables
ENV API_BASE_URL=""
ENV ADMIN_CONSOLE_URL=""
ENV ENV_NAME=""

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

# ENTRYPOINT runs path normalization and env injection, then hands off to Java
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "java $JAVA_OPTS -jar /app/acme-portal-static.jar"]
