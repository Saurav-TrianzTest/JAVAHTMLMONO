# =============================================================
# Multi-stage Dockerfile for acme-portal-static (Csat module)
# Build tool : Maven (system mvn - no wrapper)
# Java       : 17
# Runtime    : eclipse-temurin:17-jdk (explicit base image)
# Port       : 8080
# =============================================================

# ── Stage 1: Build the Java backend ──────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy POM first for dependency-layer caching
COPY pom.xml ./

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B -q

# Copy source and build the JAR
COPY src ./src
RUN mvn clean package -DskipTests -B -q

# ── Stage 2: Production image ─────────────────────────────────
FROM eclipse-temurin:17-jdk

WORKDIR /app

# Create non-root user for security
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser

# Copy compiled backend JAR
COPY --from=builder /workspace/target/acme-portal-static.jar ./app.jar

# Copy production static assets
# NOTE: .dockerignore excludes test.html, *.dev.html, build-info.html,
#       **/*.map, **/*.js.map, **/*.css.map, build logs, etc.
COPY index.html        ./index.html
COPY app/              ./app/
COPY forms/            ./forms/
COPY pages/            ./pages/
COPY partials/         ./partials/
COPY assets/css/site.css ./assets/css/site.css

# Set ownership
RUN chown -R appuser:appgroup /app

# JVM tuning for containers
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"
ENV TZ=UTC

USER appuser

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
