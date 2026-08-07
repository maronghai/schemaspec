# Stage 1: Builder
FROM zig:0.16.0 AS builder

WORKDIR /app

# Copy build files first for better caching
COPY rune/build.zig rune/build.zig.zon ./

# Copy source code
COPY rune/src/ src/

# Build release binary
RUN zig build -Doptimize=ReleaseSafe

# Stage 2: Runtime
FROM debian:bookworm-slim AS runtime

# Install ca-certificates for HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/zig-out/bin/rune /usr/local/bin/rune

# Set entrypoint
ENTRYPOINT ["rune"]
CMD ["--help"]
