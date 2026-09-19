# =============================================================================
# Multi-stage Dockerfile for acme-portal-static
# Java 17 — Plain JDK HttpServer (no Spring Boot)
# Build tool: Maven (system mvn — no wrapper)
# =============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy build descriptor first for dependency-layer caching
COPY pom.xml .

# Pre-fetch dependencies (cached unless pom.xml changes)
RUN mvn dependency:go-offline -B --quiet

# Copy the rest of the source tree
COPY src ./src

# Build the fat JAR, skip tests
RUN mvn clean package -DskipTests -B --quiet

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk

# Metadata
LABEL maintainer="trianz" \
      application="acme-portal-static" \
      version="1.0.0"

# Timezone
ENV TZ=UTC

WORKDIR /app

# Create a non-root user for security
RUN groupadd --system appgroup && \
    useradd  --system --gid appgroup --no-create-home appuser

# Copy compiled JAR from builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar app.jar

# Copy static frontend assets served alongside the backend
COPY index.html   ./
COPY app/         ./app/
COPY pages/       ./pages/
COPY forms/       ./forms/
COPY partials/    ./partials/
COPY assets/      ./assets/

# JVM tuning — container-aware heap management
ENV JAVA_OPTS="-Xms128m -Xmx384m \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+UseG1GC \
  -Djava.security.egd=file:/dev/./urandom \
  -Dfile.encoding=UTF-8 \
  -Duser.timezone=UTC"

# Application port
EXPOSE 8080

# Switch to non-root user
USER appuser

# Graceful shutdown via SIGTERM
STOPSIGNAL SIGTERM

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
