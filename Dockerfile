# =============================================================
# Multi-stage Dockerfile for acme-portal-static (Java 17)
#
# Stage 1 – builder : compiles the Java backend with Maven
# Stage 2 – runtime : minimal JRE image with production assets
# =============================================================

# ── Stage 1: Build ───────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy POM first for dependency layer caching
COPY pom.xml ./

# Download dependencies (layer cache)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application JAR (skip tests – run in CI)
RUN mvn clean package -DskipTests -B --no-transfer-progress

# Copy static assets into builder stage so we can strip build
# artifacts (*.map source maps, build logs) before the runtime
# stage picks them up.
COPY assets/ /workspace/assets/

# Remove all source-map files and build logs from the assets tree
RUN find /workspace/assets -type f \( -name "*.map" -o -name "*.js.map" -o -name "*.css.map" -o -name "build.log" -o -name "build-*.log" \) -delete

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM eclipse-temurin:17-jdk

# Non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy the compiled JAR from the builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar ./app.jar

# Copy ONLY production-safe static assets from the builder stage.
# Source maps (*.map) and build logs have already been removed in
# the builder stage. Development / test HTML files are deliberately
# NOT copied.
COPY --from=builder /workspace/assets/ ./assets/
COPY index.html        ./index.html
COPY app/              ./app/
COPY pages/            ./pages/
COPY forms/            ./forms/
COPY partials/         ./partials/

# Drop privileges
USER appuser

# Expose the application port
EXPOSE 8080

# JVM options for container-aware memory management
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Djava.security.egd=file:/dev/./urandom -Dfile.encoding=UTF-8 -Duser.timezone=UTC"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
