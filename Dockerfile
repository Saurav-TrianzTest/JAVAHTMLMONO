# =============================================================================
# Multi-stage Dockerfile for acme-portal-static
# Build tool  : Maven (system mvn — no wrapper)
# Java version: 17
# Runtime base: eclipse-temurin:17-jdk (explicit)
# Target      : GCP GKE
# =============================================================================

# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy POM first to leverage Docker layer caching for dependencies
COPY pom.xml ./

# Download dependencies (cached layer — only invalidated when pom.xml changes)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the JAR (skip tests; tests run in CI before image build)
RUN mvn clean package -DskipTests -B --no-transfer-progress

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk

# Non-root user for GKE security policy compliance
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy compiled application JAR from builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar ./app.jar

# Copy ONLY production HTML assets (development/test files excluded via .dockerignore)
COPY index.html        ./index.html
COPY app/              ./app/
COPY forms/            ./forms/
COPY pages/            ./pages/
COPY partials/         ./partials/
COPY assets/           ./assets/

# Drop to non-root user
USER appuser

# Expose the application port
EXPOSE 8080

# JVM tuning: container-aware memory management
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Xms256m -Xmx512m -Dfile.encoding=UTF-8 -Duser.timezone=UTC"
ENV PORT=8080

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
