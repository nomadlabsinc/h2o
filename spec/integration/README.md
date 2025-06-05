# Integration Tests

This directory contains integration tests for the H2O HTTP/2 client.

## Docker HTTP/2 Servers

### Setup

1. Start the test servers:
```bash
cd spec/integration
docker-compose up -d
```

2. Run integration tests:
```bash
crystal spec spec/integration/
```

3. Stop the servers:
```bash
cd spec/integration
docker-compose down
```

### Available Test Servers

- **Nginx HTTP/2** (port 8443): Full-featured HTTP/2 server with SSL
- **HTTPBin** (port 8080): HTTP testing service (HTTP/1.1 for comparison)
- **Caddy HTTP/2** (port 8444): Modern HTTP/2 server with automatic HTTPS

### Test Endpoints

#### Nginx (https://localhost:8443)
- `/` - Basic JSON response
- `/headers` - Returns request headers
- `/status/200` - Success response
- `/status/404` - Error response

#### Caddy (https://localhost:8444)
- `/health` - Health check endpoint
- `/echo` - Echo request details
- `/*` - Catch-all response

## Running Tests

### Local Tests Only
```bash
crystal spec spec/integration/http2_integration_spec.cr
```

### With Docker Servers
```bash
# Start servers
cd spec/integration && docker-compose up -d

# Run all tests including server integration
crystal spec spec/

# Stop servers
cd spec/integration && docker-compose down
```

## CI/CD Integration

The GitHub Actions workflow should:
1. Start Docker services
2. Wait for services to be healthy
3. Run all tests including integration tests
4. Stop Docker services

## Frame Initialization Tests

The integration tests specifically verify that the frame initialization fixes work correctly:
- Data frames with padding flags
- Headers frames with padding and priority flags
- Push promise frames with padding flags

These tests ensure the `@flags` instance variable initialization issue has been resolved.