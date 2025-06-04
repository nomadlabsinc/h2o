FROM robnomad/crystal:1.16.0 as builder

WORKDIR /app

# Copy shard files
COPY shard.yml shard.lock* ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY src/ ./src/

# Build the application
RUN crystal build src/h2o.cr --release --static --no-debug -o h2o

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy the built binary
COPY --from=builder /app/h2o ./

# Create non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

USER appuser

ENTRYPOINT ["./h2o"]