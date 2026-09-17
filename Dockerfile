# =============================================================================
# Multi-stage Dockerfile for acme-portal-static
# Builder : maven:3.9.6-eclipse-temurin-17
# Runtime : amazoncorretto:17  (explicit base image)
# Target  : AWS EKS
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy POM first for dependency-layer caching
COPY pom.xml .

# Pre-fetch dependencies (layer is reused unless pom.xml changes)
RUN mvn dependency:go-offline -q

# Copy application source
COPY src/ src/

# Build the JAR (skip tests — tests run in CI, not in Docker build)
RUN mvn clean package -DskipTests -q

# ── Stage 2: Production runtime ───────────────────────────────────────────────
FROM amazoncorretto:17

# Non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy compiled JAR from builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar app.jar

# Copy ONLY production HTML assets
# (test.html, build-info.html, *.map files are excluded via .dockerignore)
COPY index.html        ./
COPY app/              app/
COPY forms/            forms/
COPY pages/            pages/
COPY partials/         partials/
COPY assets/css/       assets/css/

# Copy only JS files — explicitly exclude *.map source-map build artifacts
COPY assets/js/*.js    assets/js/

# JVM tuning — container-aware memory settings
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Xms256m -Xmx512m -Dfile.encoding=UTF-8 -Duser.timezone=UTC"

# Application port
ENV PORT=8080

USER appuser

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
