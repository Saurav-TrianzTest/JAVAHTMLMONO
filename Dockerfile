# =============================================================================
# Dockerfile – acme-portal-static (JAVAHTMLMONO)
# Multi-stage build: Maven builder + Eclipse Temurin 17 JDK runtime
# Target: AWS ECS Fargate
# Health endpoint: GET /api/health
# Application port: 8080
# =============================================================================

# ── Build stage ──────────────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy POM first for dependency layer caching
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Copy source and build
COPY src/ src/
RUN mvn clean package -DskipTests -q

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk

# Install sed (required by docker-entrypoint.sh for path normalisation and
# placeholder substitution at container startup)
RUN apt-get update && apt-get install -y --no-install-recommends sed && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd --system appgroup && useradd --system --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy the compiled application JAR from builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar app.jar

# Copy static HTML assets (path normalisation runs at startup via ENTRYPOINT)
COPY pages/      pages/
COPY forms/      forms/
COPY partials/   partials/
COPY app/        app/
COPY assets/     assets/
COPY index.html  index.html
# NOTE (cz-html-1010): test.html is intentionally excluded from the production
# container image to prevent development endpoint exposure in ECS Fargate deployments.
# NOTE (cz-html-1012): build-info.html is intentionally excluded from the
# production container image to prevent build artifact exposure and image bloat.

# Copy the ENTRYPOINT normalisation script and make it executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app /usr/local/bin/docker-entrypoint.sh

# Set the HTML root so the entrypoint script knows where to scan
ENV HTML_ROOT=/app

# JVM memory settings optimised for ECS Fargate containers
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

# CONTAINERIZATION FIX (cz-html-1007): TELEMETRY_BASE_URL injected at runtime
# from AWS Secrets Manager via ECS Fargate task definition secrets block.
ENV TELEMETRY_BASE_URL=""

# CONTAINERIZATION FIX (cz-html-1008): CDN_BASE_URL injected at runtime
# from AWS Secrets Manager via ECS Fargate task definition secrets block.
ENV CDN_BASE_URL=""

# CONTAINERIZATION FIX (cz-html-1011): STATIC_ASSETS_BASE_URL and API_BASE_URL
# injected at runtime from AWS SSM Parameter Store via ECS Fargate task definition.
ENV STATIC_ASSETS_BASE_URL=""
ENV API_BASE_URL=""

# CONTACT_API_URL injected at runtime from AWS Secrets Manager
ENV CONTACT_API_URL=""

# TIMESTAMP_RENDER_MODE injected at runtime from AWS Secrets Manager
ENV TIMESTAMP_RENDER_MODE=""

# Timezone configuration
ENV TZ=UTC

# Expose the application port
EXPOSE 8080

# Switch to non-root user
USER appuser

# Run path normalisation first, then start the Java application
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["java", "-jar", "/app/app.jar"]
