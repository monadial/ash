# =============================================================================
# ASH Backend - Multi-stage Dockerfile
# =============================================================================
#
# Optimized for:
# - Fast rebuilds via cargo-chef dependency caching
# - Minimal final image size (~25MB)
# - Security (non-root user, minimal attack surface)
#
# Build: docker build -t ash-backend .
# Run:   docker run -p 8080:8080 ash-backend
#
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Chef - Install cargo-chef for dependency caching
# -----------------------------------------------------------------------------
FROM rust:1.75-slim-bookworm AS chef

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install cargo-chef --locked

WORKDIR /app

# -----------------------------------------------------------------------------
# Stage 2: Planner - Analyze dependencies and create recipe
# -----------------------------------------------------------------------------
FROM chef AS planner

COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Generate recipe.json for dependency caching
RUN cargo chef prepare --recipe-path recipe.json

# -----------------------------------------------------------------------------
# Stage 3: Builder - Build dependencies (cached) then application
# -----------------------------------------------------------------------------
FROM chef AS builder

# Build dependencies first (cached unless Cargo.toml/Cargo.lock change)
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# Build application
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release --locked

# Verify binary exists and strip it (extra strip for good measure)
RUN strip /app/target/release/ash-backend

# -----------------------------------------------------------------------------
# Stage 4: Runtime - Minimal production image
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/cc-debian12:nonroot AS runtime

# Labels for container metadata
LABEL org.opencontainers.image.title="ASH Backend"
LABEL org.opencontainers.image.description="Minimal untrusted message relay for ephemeral encrypted messaging"
LABEL org.opencontainers.image.source="https://github.com/monadial/ash"
LABEL org.opencontainers.image.licenses="MIT"

# Copy the compiled binary
COPY --from=builder --chown=nonroot:nonroot /app/target/release/ash-backend /ash-backend

# Expose the default port
EXPOSE 8080

# Set default environment variables
ENV BIND_ADDR=0.0.0.0
ENV PORT=8080
ENV RUST_LOG=ash_backend=info,tower_http=info

# Run as non-root user (distroless:nonroot UID=65532)
USER nonroot:nonroot

# Health check endpoint
# Note: distroless doesn't have curl, so we rely on orchestrator health checks
# For Kubernetes: use livenessProbe with httpGet to /health

# Run the binary
ENTRYPOINT ["/ash-backend"]
