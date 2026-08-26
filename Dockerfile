# =============================================================================
# Multi-stage Dockerfile for acme-portal-static
# Java 17 Maven application – plain JDK HttpServer (no Spring Boot)
# Runtime base image: mcr.microsoft.com/openjdk/jdk:17-ubuntu (explicit)
# Target platform: AWS EKS
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1 – Build the Java backend
# ---------------------------------------------------------------------------
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy Maven descriptor first for dependency-layer caching
COPY pom.xml .

# Pre-download dependencies (cached unless pom.xml changes)
RUN mvn dependency:go-offline -q

# Copy Java sources and build the JAR
COPY src/ src/
RUN mvn clean package -DskipTests -q

# ---------------------------------------------------------------------------
# Stage 2 – Assemble the minimal production image
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/openjdk/jdk:17-ubuntu AS production

# Set timezone and locale
ENV TZ=UTC \
    LANG=en_US.UTF-8 \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"

WORKDIR /app

# Create a non-root user for security
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

# Copy the compiled JAR from the builder stage
COPY --from=builder /workspace/target/acme-portal-static.jar app.jar

# Copy production HTML assets
COPY index.html        ./index.html
COPY app/              ./app/
COPY pages/            ./pages/
COPY partials/         ./partials/
COPY forms/            ./forms/

# Copy production CSS assets only (source maps excluded via .dockerignore)
COPY assets/css/site.css ./assets/css/site.css

# NOTE: test.html, build-info.html, and assets/js/app.js.map are NOT copied.
# They are excluded from the build context via .dockerignore.

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

USER appuser

# Expose the application port
EXPOSE 8080

# Run the application with JVM optimizations
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
