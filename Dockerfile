FROM crystallang/crystal:1.16.3 as builder

WORKDIR /app

# Copy shard files
COPY shard.yml shard.lock* ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY src/ ./src/

# Build the application without static linking for Ubuntu
RUN crystal build src/h2o.cr --release --no-debug -o h2o

# Runtime stage - Use Ubuntu instead of Alpine
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y ca-certificates libssl3 libevent-2.1-7 libgc1 libpcre3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built binary
COPY --from=builder /app/h2o ./

# Create non-root user
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -m -s /bin/bash appuser

USER appuser

ENTRYPOINT ["./h2o"]
