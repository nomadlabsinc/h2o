# Test Environment Setup

This document explains how to set up and run the complete test environment for the H2O HTTP/2 client library.

## Overview

The test environment includes:
- **Local Docker test servers** for fast, reliable integration testing
- **Unit tests** for core functionality
- **Performance tests** for optimization validation
- **Integration tests** with real HTTP/2 servers
- **CI/CD pipeline** with identical environment

## Prerequisites

- Crystal 1.16.3
- Docker and Docker Compose
- curl (for server health checks)

## Quick Start

### 1. Start Local Test Servers

```bash
cd spec/integration
docker compose up -d
```

This starts:
- **Nginx HTTP/2 server** on port 8443 (HTTPS)
- **HTTPBin service** on port 8080 (HTTP/1.1)
- **Caddy HTTP/2 server** on port 8444 (HTTPS)
- **HTTP/2-only server** on port 8447 (HTTPS, rejects HTTP/1.1)

### 2. Verify Servers Are Running

```bash
# Check all services
docker compose ps

# Test connectivity
curl -k https://localhost:8443/       # Nginx
curl -k https://localhost:8447/health # HTTP/2-only server
curl http://localhost:8080/get        # HTTPBin
```

### 3. Run Tests

```bash
# All tests (recommended)
crystal spec

# Individual test categories
crystal spec spec/h2o/              # Unit tests
crystal spec spec/performance/      # Performance tests
crystal spec spec/integration/      # Integration tests with local servers
```

### 4. Stop Test Servers

```bash
cd spec/integration
docker compose down
```

## Test Categories

### Unit Tests (`spec/h2o/`)
- **Purpose**: Test core library functionality
- **Speed**: Fast (~20 seconds)
- **Dependencies**: None (no network calls)
- **Coverage**: Frames, HPACK, connections, protocols

### Performance Tests (`spec/performance/`)
- **Purpose**: Validate optimizations and benchmarks
- **Speed**: Fast (~4 seconds)
- **Dependencies**: None
- **Coverage**: Buffer pooling, I/O optimization, HPACK performance

### Integration Tests (`spec/integration/`)
- **Purpose**: Test with real HTTP/2 servers
- **Speed**: Medium (~30 seconds with local servers)
- **Dependencies**: Docker test servers
- **Coverage**: Full HTTP/2 protocol compliance, real-world scenarios

## Local Test Servers

### Nginx HTTP/2 Server (`:8443`)
- **Purpose**: Full-featured HTTP/2 server
- **Endpoints**:
  - `/` - Basic JSON response
  - `/headers` - Request headers
  - `/status/200` - Success response
  - `/status/404` - Error response
- **SSL**: Self-signed certificates

### HTTP/2-Only Server (`:8447`)
- **Purpose**: Validates HTTP/2-only operation
- **Endpoints**:
  - `/health` - Health check
  - `/headers` - Headers and protocol info
  - `/status/200` - Simple success
- **Behavior**: Rejects HTTP/1.1 with 426 responses

### HTTPBin (`:8080`)
- **Purpose**: HTTP/1.1 comparison and fallback testing
- **Endpoints**: Standard HTTPBin API
- **Protocol**: HTTP/1.1 only

### Caddy (`:8444`)
- **Purpose**: Modern HTTP/2 server validation
- **Endpoints**:
  - `/health` - Health check
  - `/echo` - Echo request details
- **Features**: Automatic HTTPS, modern TLS

## Development Workflow

### Running Tests During Development

```bash
# Quick feedback loop (unit tests only)
crystal spec spec/h2o/

# Full validation before commit
cd spec/integration && docker compose up -d
crystal spec
cd spec/integration && docker compose down
```

### Adding New Tests

1. **Unit tests**: Add to `spec/h2o/`
2. **Integration tests**: Add to `spec/integration/`
3. **Use local servers**: Reference `httpbin_url()` and `http2_only_url()` helpers
4. **Follow patterns**: Use existing retry logic for reliability

### Performance Testing

```bash
# Run performance benchmarks
crystal spec spec/performance/

# Individual performance tests
crystal spec spec/performance/hpack_benchmarks_spec.cr
crystal spec spec/performance/io_optimization_*_spec.cr
```

## CI/CD Integration

The GitHub Actions CI pipeline uses the same Docker infrastructure:

### CI Jobs

1. **Test with Local Servers**
   - Starts Docker services
   - Runs all test categories
   - Uses `robnomad/crystal:dev-hoard` image

2. **Unit Tests Only (Fast)**
   - Quick feedback for PRs
   - No Docker dependencies
   - Runs in ~2 minutes

3. **Lint**
   - Crystal formatting
   - Ameba linting

4. **Build**
   - Release build
   - Documentation generation

### CI Commands

The CI uses identical commands to local development:

```bash
# Same as local
crystal spec spec/h2o/ --verbose
crystal spec spec/performance/ --verbose
crystal spec spec/integration/ --verbose
```

## Environment Parity

| Aspect | Local | CI |
|--------|-------|-----|
| Crystal Version | 1.16.3 | 1.16.3 (`robnomad/crystal:dev-hoard`) |
| Test Servers | Docker Compose | GitHub Services |
| Commands | `crystal spec` | `crystal spec` |
| SSL Certificates | Self-signed | Self-signed |
| Test URLs | `localhost:8443` | `localhost:8443` |
| Timeouts | 5 seconds | 5 seconds |

## Troubleshooting

### Test Servers Won't Start

```bash
# Check Docker
docker compose ps
docker compose logs

# Check ports
lsof -i :8443
lsof -i :8447

# Restart services
docker compose down
docker compose up -d
```

### SSL Certificate Issues

```bash
# Verify certificates exist
ls -la spec/integration/ssl/

# Test with curl (ignore cert validation)
curl -k https://localhost:8443/
```

### Test Failures

```bash
# Run with verbose output
crystal spec spec/integration/ --verbose

# Check server logs
docker compose logs nginx-h2
docker compose logs h2-only-server
```

### Performance Issues

```bash
# Check server resource usage
docker stats

# Reduce test load
# Edit test files to use fewer iterations
```

## Configuration

### Timeouts

Tests use reduced timeouts for speed:
- **Client timeout**: 5 seconds (was 10s)
- **Retry delays**: 0.3s backoff (was 0.5s)
- **Max retries**: 2 attempts (was 3)

### Test URLs

Helper functions provide consistent URLs:
```crystal
def test_base_url
  "https://localhost:8443"
end

def http2_only_url(path = "")
  "https://localhost:8447#{path}"
end
```

### Docker Configuration

Services are defined in `spec/integration/docker-compose.yml` with:
- Health checks
- Volume mounts for configs
- Consistent port mappings
- Platform compatibility

## Benefits

1. **Speed**: Local servers are ~10x faster than external services
2. **Reliability**: No network dependencies or rate limits
3. **Consistency**: Same environment locally and in CI
4. **Debugging**: Full control over test servers
5. **Offline**: Works without internet connection
6. **Performance**: 5.6x improvement through maximum parallelization
